module TransportP {
	provides interface Transport;
	
	uses interface LinkStateRouting as Routing;
	uses interface SimpleSend as Sender;
	
	uses interface List<socket_t> as SocketList;		//Pushed in during bind (client & server side)
	uses interface Hashmap<socket_store_t> as SocketMap;
	uses interface List<connection_t> as ConnectList; //Pushed in upon receipt of SYN packet (server side)
																	
	uses interface Timer<TMilli> as SendTimer;		//Every time fired, send data from socket send buffers
	uses interface Timer<TMilli> as Timeout;
	uses interface List<pack> as Unacked;
}
implementation {
	static uint8_t socketID = 0;
	static uint8_t portID = 128;
	status_t status[MAX_NUM_OF_SOCKETS]; //A sequece number per connection
	
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
	void makeTCPPack(tcp_pack *Package, uint8_t src, uint8_t dest, uint8_t seq, uint8_t ack, uint8_t flags, uint8_t ad_win, uint8_t*, uint8_t);
	void initSocket(socket_store_t* socket, enum socket_state state, socket_port_t port);
	void printSockets(void);
	void printSocketStates(void);
	void printSocketReceiveBuffer(socket_t fd);
	void printSocketSendBuffer(socket_t fd);
	void removeFromSocketList(socket_t fd);
	socket_t getSocketByDestination(socket_addr_t dest);
	void printUnacked();
	int8_t getUnacked(pack* isUnacked);
	void cleanUnacked(socket_t fd, uint16_t seq);
	void emptyUnacked(socket_t fd);
	socket_t isPendingConnection(connection_t conn);
	bool isValidSequence(socket_t fd, uint16_t seq);
	uint8_t sequenceToIndex(socket_t fd, uint16_t seq);
	void addToUnacked(socket_t fd, pack p);
	void removeFromUnacked(socket_t fd, uint8_t seq);
	void removeLessThanSeqFromUnacked(socket_t fd, uint8_t seq);
	
	command socket_t Transport.socket() {
		socket_t sock = ++socketID;
		if(sock <= MAX_NUM_OF_SOCKETS) {
			return sock;
		}
		return NULL;
	}
	
	command error_t Transport.bind(socket_t fd, socket_addr_t *addr) { 
		socket_store_t socket;
		uint8_t port = addr->port;
		
		//Check if the port we are trying to bind the socket to is already in use by a different socket
		if(call Transport.getSocketFd(port) != 0) {
			printf("Error! Port %d already bound to socket %d\n", port, call Transport.getSocketFd(port));
			return FAIL;
		}

		//If this socket is not already in use, initialize it with the new address
		if(!call SocketMap.contains((uint32_t) fd)) {
			initSocket(&socket, CLOSED, port);
			call SocketMap.insert((uint32_t) fd, socket);
			call SocketList.pushback(fd);
			return SUCCESS;
		}

		return FAIL;
	}
	
	command error_t Transport.listen(socket_t fd) {
		socket_store_t socket = call SocketMap.get((uint32_t) fd);
		
		if(socket.state == CLOSED && fd != 0) {
			socket.state = LISTEN;
			call SocketMap.update((uint32_t) fd, socket);
			return SUCCESS;
		}
		
		return FAIL;	 
	}
	
	command error_t Transport.connect(socket_t fd, socket_addr_t *dest) {
		socket_store_t socket = call SocketMap.get((uint32_t) fd);
		pack myPack;
		tcp_pack mySyn;
		
		if(socket.state == CLOSED) {
			//Set an initial sequence number
			status[fd].isn = 32*(TOS_NODE_ID*fd - 1) + (63 * fd * (fd+3));
			status[fd].seq = status[fd].isn;
			status[fd].startOfWindow = 0;
			status[fd].endOfWindow = TCP_MAX_PAYLOAD_SIZE * SOCKET_BUFFER_WINDOW_SIZE - 1;
			status[fd].isFirstDataReadSend = TRUE;
			status[fd].isFirstDataReadRcvd = TRUE;
			status[fd].isFirstDataWriteSend = TRUE;
			status[fd].isFirstDataWriteRcvd = TRUE;
			status[fd].isActive = TRUE;
			status[fd].unackedSize = 0;
			//Create a TCP SYN packet, set the flag to 1 (SYN)
			makeTCPPack(&mySyn, socket.src, dest->port, status[fd].seq++, 0, 0x01, SOCKET_BUFFER_SIZE, NULL, 0);
			//Encapsulate into packet struct
			makePack(&myPack, TOS_NODE_ID, dest->addr, MAX_TTL, PROTOCOL_TCP, 0, &mySyn, PACKET_MAX_PAYLOAD_SIZE);
			//Send TCP SYN packet out
			call Sender.send(myPack, call Routing.getNextHopTo(dest->addr));
			//Change the state of the socket
			socket.state = SYN_SENT;
			call SocketMap.update((uint32_t) fd, socket);
			dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to SYN_SENT\n", fd);
			
			//Add an entry for this pack in Unacked
			status[fd].sentTime = call Timeout.getNow();
			myPack.TTL = fd;
			call Unacked.pushback(myPack);
			
			call Timeout.startPeriodic(800000);
			
			return SUCCESS;
		}
		printf("Socket %d closed\n", fd);
		return FAIL;
	}
	
	command socket_t Transport.accept(socket_t fd) {
		socket_store_t socket = call Transport.getSocket(fd);
		uint8_t i, size = call ConnectList.size();
		connection_t connectionRequest;
		socket_store_t newSocket;
		socket_addr_t newAddress;
		socket_t newFd;
		tcp_pack tcpSend;
		pack sendPack;
		bool resend = FALSE;

		//Return 0 if socket is not listening
		if(socket.state != LISTEN) {
			dbg(TRANSPORT_CHANNEL, "Socket %d not accepting connection requests\n", fd);
			return 0;
		}
		
		//Check all connection requests
		for(i = 0; i < size; i++) {
			connectionRequest = call ConnectList.get(i);
			//If there is a connection request for the fd pass to this accept() call
			if(connectionRequest.fd == fd) {				
				//Check if this is a duplicate request
				newFd = isPendingConnection(connectionRequest);
				if(newFd > 0) {
					printf("Connection attempt from %d:%d already initiated on socket %d\n", 
						connectionRequest.dest.addr, connectionRequest.dest.port, newFd
					);
					resend = TRUE;
				}
				else {
					printf("New connection attempt from %d:%d to port %d\n", 
						connectionRequest.dest.addr,connectionRequest.dest.port, connectionRequest.src.port
					);
					newFd = call Transport.socket();
				}
								
				//If socket was successfully aquired, try to bind to a new port
				if(newFd != 0) {
					newAddress.addr = TOS_NODE_ID;
					newAddress.port = portID;
					//If binding was successful, initialize data structures for new socket
					if(call Transport.bind(newFd, &newAddress) == SUCCESS) {	
						//Initialize new socket
						newSocket = call Transport.getSocket((uint32_t) newFd);					
						newSocket.dest.addr = connectionRequest.dest.addr;
						newSocket.dest.port = connectionRequest.dest.port;
						newSocket.state = SYN_RCVD;
						//Initialize status info
						status[newFd].isn = connectionRequest.isn;
						status[newFd].seq = status[fd].isn;
						status[newFd].startOfWindow = 0;
						status[newFd].endOfWindow = TCP_MAX_PAYLOAD_SIZE * SOCKET_BUFFER_WINDOW_SIZE - 1;
						status[newFd].isFirstDataReadSend = TRUE;
						status[newFd].isFirstDataReadRcvd = TRUE;
						status[newFd].isFirstDataWriteSend = TRUE;
						status[newFd].isFirstDataWriteRcvd = TRUE;
						status[newFd].isActive = TRUE;
						status[newFd].unackedSize = 0;
						
						call SocketMap.update((uint32_t)newFd, newSocket);
						
						dbg(TRANSPORT_CHANNEL, "Successfully bound new socket %d to port %d\n", newFd, portID);
						dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to SYN_RCVD\n", newFd);

						portID++;
					}
					else if(resend == TRUE) {
						newSocket = call SocketMap.get((uint32_t) newFd);
						printf("Need to resend SYN+ACK to %d:%d\n", newSocket.dest.addr, newSocket.dest.port);
					}
					else {
						printf("Unable to bind socket %d to port %d\n", newFd, newAddress.port);
						return 0;
					}
					//Send SYN+ACK to requesting client
					dbg(TRANSPORT_CHANNEL, "Sending SYN+ACK to %d:%d\n", newSocket.dest.addr, newSocket.dest.port);
					makeTCPPack(&tcpSend, newSocket.src, newSocket.dest.port, status[newFd].seq++, connectionRequest.isn, 3, SOCKET_BUFFER_SIZE, NULL, 0);
					makePack(&sendPack, TOS_NODE_ID, newSocket.dest.addr, MAX_TTL, PROTOCOL_TCP, 0, &tcpSend, PACKET_MAX_PAYLOAD_SIZE);;
					call Sender.send(sendPack, call Routing.getNextHopTo(sendPack.dest));
					
					call ConnectList.remove(i);
				}
				else {
					printf("Unable to obtain new socket for %d:%d\n", connectionRequest.dest.addr, connectionRequest.dest.port);
					return 0;
				}
			}
		}
	}
	
	//Read [bufflen] values from the socket [fd] and write to the buffer [buff]
	command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
		uint8_t numRead = 0;
		uint8_t readSize; //, readBeforeWrap, readAfterWrap;
		uint8_t nextRead;
		int8_t offset;
		socket_store_t socket = call SocketMap.get((uint32_t) fd);
		pack packet;
		tcp_pack *toNotifyOfAvailBuffSpace;

		//No available data to read
		if(socket.lastRead == socket.lastRcvd) { return 0; }
		
		//Total number of values that can be read from the socket receive buffer
		readSize = status[fd].toReceive;
		printf("Socket %d has %d values to read\n", fd, readSize);
		
		//Index of the next value to read from the socket receive buffer
		nextRead = (status[fd].isFirstDataReadRcvd == TRUE) ? socket.lastRead : (socket.lastRead + 1) % SOCKET_BUFFER_SIZE;
//		printf("Next read is at %d\n", nextRead);
		
		if(readSize > bufflen) readSize = bufflen;
//		printf("ReadSize is %d\n", readSize);

		//If there are values to read from the socket buffer
		if(readSize > 0) {
			printf((status[fd].isFirstDataReadRcvd == TRUE) ? "First read\n" : "Not first read\n");
			
			//Read them into the global buffer pointed to by [buff]
			for(numRead = 0, offset = 0; numRead < readSize; numRead++, offset++) {
				if(nextRead + numRead == SOCKET_BUFFER_SIZE) {
					offset = -(SOCKET_BUFFER_SIZE - numRead);
				}
				*(buff + offset) = socket.rcvdBuff[(nextRead + numRead) % SOCKET_BUFFER_SIZE];
//				printf("Reading %c\n",*(buff + offset));
			}
//			printf("Read %d into socket %d global buffer\n", numRead, fd);
			
			socket.lastRead += (status[fd].isFirstDataReadRcvd == TRUE) ? numRead - 1: numRead;
			socket.lastRead %= SOCKET_BUFFER_SIZE;
			call SocketMap.update((uint32_t) fd, socket);
			
			packet = status[fd].lastAckSent;
			toNotifyOfAvailBuffSpace = (tcp_pack*) packet.payload;
			if(toNotifyOfAvailBuffSpace->ad_win == 0) {
				toNotifyOfAvailBuffSpace->ad_win = numRead;
//				printf("\nNotifying sender of available buffer space\n");
				packet.TTL = fd;
				call Unacked.pushback(packet);
				call Timeout.startPeriodic(65536);
				call Sender.send(packet, call Routing.getNextHopTo(packet.dest));
			}
		}
		
		if(numRead > 0) {
			status[fd].endOfWindow += numRead;
			status[fd].endOfWindow %= SOCKET_BUFFER_SIZE;
		
			status[fd].startOfWindow += numRead;
			status[fd].startOfWindow %= SOCKET_BUFFER_SIZE;
		
			status[fd].isFirstDataReadRcvd = FALSE;
			status[fd].toReceive -= numRead;
			
			printSocketReceiveBuffer(fd);
		}
		
		return numRead;
	}
	
	//Write [bufflen] values to the socket with file descriptor [fd] from the buffer [buff]
	command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) { 
		socket_store_t socket = call SocketMap.get((uint32_t) fd);
		uint8_t nextWrite, safeToWrite, endOfWindow, windowSize = TCP_MAX_PAYLOAD_SIZE * SOCKET_BUFFER_WINDOW_SIZE;
		uint8_t numWritten = 0;
		bool wrap;
		
		if(bufflen == 0) return 0;
		
//		printf("Client wants to write %d values to socket %d send buffer\n", bufflen, fd);
		
		//The index of the next value to be written to the socket send buffer
		nextWrite = (status[fd].isFirstDataWriteSend == TRUE) ? 0 : (socket.lastWritten + 1) % SOCKET_BUFFER_SIZE;
//		printf("The next index to write is at %d\n", nextWrite);
		
		//The index of the end of the window
		endOfWindow = (status[fd].isFirstDataWriteSend == TRUE) ? socket.lastAck + windowSize - 1 : socket.lastAck + windowSize;
		endOfWindow %= SOCKET_BUFFER_SIZE;
//		printf("The end of the window is at %d\n", status[fd].endOfWindow);
		
		if(socket.lastWritten == endOfWindow || nextWrite == endOfWindow) { 
//			printf("Cannot write past end of window, returning 0\n\n");
			return 0;
		}
		
		//The number of values it is safe to write to the buffer, limited by window size
		safeToWrite = (nextWrite < endOfWindow) ? endOfWindow - nextWrite + 1 : (SOCKET_BUFFER_SIZE - nextWrite) + endOfWindow + 1;
		safeToWrite = (safeToWrite > bufflen) ? bufflen : safeToWrite;
//		printf("It is safe to write %d more values\n", safeToWrite);
		
		if(safeToWrite > 0) {
			printf("Writing %d to send buffer at position %d\n", safeToWrite, nextWrite);
			printf((status[fd].isFirstDataWriteSend == TRUE) ? "First write\n" : "Not first write\n");
			for(numWritten = 0; numWritten < safeToWrite; numWritten++) {
//				printf("Writing %c from %d\n", *(buff + offset), offset);
				socket.sendBuff[(nextWrite + numWritten) % SOCKET_BUFFER_SIZE] = *(buff + numWritten);
//				printf("Writing %c\n", (char)*(buff + offset));
			}
			
			socket.lastWritten += (status[fd].isFirstDataWriteSend == TRUE) ? numWritten - 1 : numWritten;
			socket.lastWritten %= SOCKET_BUFFER_SIZE;
			
			call SocketMap.update((uint32_t) fd, socket);
		}
		
		if(numWritten > 0) status[fd].isFirstDataWriteSend = FALSE;
		status[fd].toSend += numWritten;
		printf("write() returning %d\n\n", numWritten);
		
		if(!call SendTimer.isRunning() && socket.state == ESTABLISHED) { call SendTimer.startPeriodic(1024*128); }
		
		printSocketSendBuffer(fd);
		
		return numWritten;
	}
	
	command error_t Transport.close(socket_t fd) { 
		tcp_pack 		myTCP;
		pack				sendPackage;
		socket_store_t socket = call SocketMap.get((uint32_t) fd);
		
		dbg(TRANSPORT_CHANNEL, "Closing socket %d\n", fd);
		dbg(TRANSPORT_CHANNEL, "Sending FIN to address: %d, port: %d\n", socket.dest.addr, socket.dest.port);
		
		//TODO: Check if there are packets left to ack, ack if so
		makeTCPPack(&myTCP, socket.src, socket.dest.port, 74, 74, 0x04, SOCKET_BUFFER_SIZE, NULL, 0);
		makePack(&sendPackage, TOS_NODE_ID, socket.dest.addr, MAX_TTL, PROTOCOL_TCP, 0, &myTCP, PACKET_MAX_PAYLOAD_SIZE);
		
		if(call Sender.send(sendPackage, call Routing.getNextHopTo(socket.dest.addr)) == SUCCESS) {
			socket.state == CLOSED;
			call SocketMap.update((uint32_t) fd, socket);
			removeFromSocketList(fd);
			dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to CLOSED\n", fd);
			return SUCCESS;
		}
		return FAIL;
	}
	
	command error_t Transport.release(socket_t fd) { }
	
	command error_t Transport.receive(pack* myMsg) { 
		pack 		 sendPackage;
		tcp_pack* tcpRcvd = (tcp_pack*) myMsg->payload;
      tcp_pack  tcpSend;
      
      socket_t fd;
      socket_store_t socket;
      connection_t newConnection;
      
      uint8_t windowSize = TCP_MAX_PAYLOAD_SIZE * SOCKET_BUFFER_WINDOW_SIZE;
      uint8_t advertisedWindow;
      int8_t i, nextRcvd;
      
      //Make sure the incoming message is for a valid socket/port 			   	
		if((fd = call Transport.getSocketFd(tcpRcvd->dest_port)) == NULL) {
			dbg(TRANSPORT_CHANNEL, "Error! Communication attempt to a socket(%d) that does not exist\n", fd);
			return FAIL;
		}
	 	
		socket = call SocketMap.get((uint32_t) fd);
      
      printf("\n");
		dbg(TRANSPORT_CHANNEL, "TCP Payload: src_port: %d, dest_port: %d, seq: %d, ack: %d, flags: %d, ad_win: %d\n", 
			tcpRcvd->src_port, tcpRcvd->dest_port, tcpRcvd->seq, tcpRcvd->ack, tcpRcvd->flags, tcpRcvd->ad_win);
			
		switch(tcpRcvd->flags) {
		//===========================================SYN==============================================================
		case 0x01:
			dbg(TRANSPORT_CHANNEL, "SYN received from %d:%d with isn: %d\n", myMsg->src, tcpRcvd->src_port, tcpRcvd->seq);

			//Create a new connection_t from this syn packet and push into ConnectList for accept() call to handle
			if(socket.state == LISTEN) {
				newConnection.fd = fd;
				newConnection.src.addr = TOS_NODE_ID;
				newConnection.src.port = tcpRcvd->dest_port;
				newConnection.dest.addr = myMsg->src;
				newConnection.dest.port = tcpRcvd->src_port;
				newConnection.isn = tcpRcvd->seq;
				call ConnectList.pushback(newConnection);
//				printf("Added new connection attempt information\n");
			}
			break;
			
		//===========================================ACK==============================================================
		case 0x02:
//			dbg(TRANSPORT_CHANNEL, "ACK received from %d:%d for sequence number %d\n", myMsg->src, tcpRcvd->src_port, tcpRcvd->ack);
		
			if(socket.state == ESTABLISHED) {
				//When we receive a duplicate ack due to receiver now having available buffer, update the effective window
				if(sequenceToIndex(fd, tcpRcvd->ack) == socket.lastAck) {
//					printf("Duplicate ACK\n");
//					printf("Receivers advertised window = %d\n", tcpRcvd->ad_win);
					socket.effectiveWindow = tcpRcvd->ad_win;
//					printf("Receivers effective window = %d\n", socket.effectiveWindow);
		  			call SocketMap.update((uint32_t) fd, socket);
					break;
				}
				
				socket.lastAck = sequenceToIndex(fd, tcpRcvd->ack);
				socket.nextExpected = tcpRcvd->seq + 1;
//				printf("Receivers advertised window = %d\n", tcpRcvd->ad_win);
				socket.effectiveWindow = tcpRcvd->ad_win;
				status[fd].endOfWindow += TCP_MAX_PAYLOAD_SIZE;
				status[fd].endOfWindow %= SOCKET_BUFFER_SIZE;
//				printf("Sliding Window! Window is now [%d -> %d]\n", socket.lastAck + 1, status[fd].endOfWindow);
				
//				printf("Cleaning unacked less than %d\n", tcpRcvd->ack);
				cleanUnacked(fd, tcpRcvd->ack);
				removeLessThanSeqFromUnacked(fd, tcpRcvd->ack);
//				printUnacked();
				//Remove entry for this packet in Unacked
				if((i = getUnacked(myMsg)) != -1) call Unacked.remove(i);
			}
			if(socket.state == SYN_RCVD) { 	//Server side, this is the final ack of the handshake
		  		//Change state of socket bound to dest_port to ESTABLISHED
		  		socket.state = ESTABLISHED;
		  		socket.dest.addr = myMsg->src;
		  		socket.dest.port = tcpRcvd->src_port;
		  		socket.nextExpected = tcpRcvd->seq + 1;
		  		
		  		dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to ESTABLISHED\n", fd);

				//Remove entry for this packet in Unacked
				if((i = getUnacked(myMsg)) != -1) call Unacked.remove(i);
				
		  		//Connection established (server)
		  		signal Transport.acceptDone(fd);
		  	}
		  	call SocketMap.update((uint32_t) fd, socket);
			break;
			
		//========================================SYN+ACK=============================================================
		case 0x03:
			dbg(TRANSPORT_CHANNEL, "SYN+ACK received from %d:%d\n", myMsg->src, tcpRcvd->src_port);
			
			if(socket.state == SYN_SENT) {
				//Remove entry for this packet in Unacked
				if((i = getUnacked(myMsg)) != -1) call Unacked.remove(i);
				//Measure RTT
				status[fd].rcvdTime = call Timeout.getNow();
				socket.RTT = status[fd].rcvdTime - status[fd].sentTime;
				//Change the state of socket bound to dest_port to ESTABLIHED
				socket.state = ESTABLISHED;
			  	socket.dest.addr = myMsg->src;
				socket.dest.port = tcpRcvd->src_port;
			  	call SocketMap.update((uint32_t) fd, socket);
			  	//Send ack
			  	dbg(TRANSPORT_CHANNEL, "Sending ACK to %d:%d\n", myMsg->src, tcpRcvd->src_port);
			  	makeTCPPack(&tcpSend, tcpRcvd->dest_port, tcpRcvd->src_port, status[fd].seq++, tcpRcvd->seq, 0x02, SOCKET_BUFFER_SIZE, NULL, 0);
				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, 0, &tcpSend, PACKET_MAX_PAYLOAD_SIZE);
				call Sender.send(sendPackage, call Routing.getNextHopTo(sendPackage.dest));
			  	dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to ESTABLISHED\n", fd);
				//Start SendTimer and signal connectDone			  	
			  	call SendTimer.startPeriodic(1024*128);
				signal Transport.connectDone(fd);
			}
			else {
				printf("Socket %d not expecting SYN+ACK\n", fd);			
			}
			
			break;
		//===========================================FIN===============================================================
	/*	case 0x04: 
			//Connection closed
		  	dbg(TRANSPORT_CHANNEL, "FIN received from %d:%d\n", myMsg->src, tcpRcvd->src_port);
		  	//Change the state of socket bound to dest_port to CLOSED
		  	socket.state = CLOSED;
		  	call SocketMap.update((uint32_t) fd, socket);
		  	dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to CLOSED\n", fd);
		  	//Send fin
		  	dbg(TRANSPORT_CHANNEL, "Sending FIN to %d:%d\n", myMsg->src, tcpRcvd->src_port);
		  	makeTCPPack(&tcpSend, tcpRcvd->dest_port, tcpRcvd->src_port, 44, 44, 0x04, SOCKET_BUFFER_SIZE, NULL, 0);
			makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, 0, &tcpSend, PACKET_MAX_PAYLOAD_SIZE);
			call Sender.send(sendPackage, call Routing.getNextHopTo(sendPackage.dest));
		  	break;*/
		//===========================================DATA==============================================================
		default:
			if(socket.state == ESTABLISHED) {
//				printf("Received data from %d:%d!\n", myMsg->src, tcpRcvd->src_port);
//				printf("The end of the window is %d\n", status[fd].endOfWindow);
				printf("%d\n", socket.nextExpected);
				if(tcpRcvd->seq == socket.nextExpected) {	//TODO: Client cant receive messages due to sequence number problem
				
					//The Unacked list on the server side is for retransmission of the duplicate acks used for flow control
					//If this block is reached, we can imply that the ack had been received and empty the list
					emptyUnacked(fd);
				
					nextRcvd = (status[fd].isFirstDataWriteRcvd == TRUE) ? socket.lastRcvd : (socket.lastRcvd + 1) % SOCKET_BUFFER_SIZE;
					
//					printf("Writing %d values to socket %d receive buffer at %d\n", tcpRcvd->ad_win, fd, nextRcvd);
					printf((status[fd].isFirstDataWriteRcvd == TRUE) ? "First write\n" : "Not firt write\n");
					
					for(i = 0; i < tcpRcvd->ad_win; i++) {
						//If buffer wraps, continue reading at index 0
						if(nextRcvd + i >= SOCKET_BUFFER_SIZE) nextRcvd = -i;
						socket.rcvdBuff[nextRcvd + i] = tcpRcvd->payload[i];
					}
					
//					printf("windowSize(%d), nextExpected(%d), lastRead(%d), endOfWindow(%d)\n", 
//							windowSize, sequenceToIndex(fd, socket.nextExpected) + 1, socket.lastRead, status[fd].endOfWindow);
					
					//TODO: Calculate the advertised window
					if(sequenceToIndex(fd, socket.nextExpected) <= status[fd].endOfWindow + 1) {
						advertisedWindow = status[fd].endOfWindow - sequenceToIndex(fd, socket.nextExpected);
					}
					else {
						advertisedWindow = (SOCKET_BUFFER_SIZE - sequenceToIndex(fd, socket.nextExpected) - 1) + (status[fd].endOfWindow + 1);
					}
					
//					printf("Advertised window: %d\n", advertisedWindow);
					
//					printf("lastrcvd = %d\n", socket.lastRcvd);
					
					socket.lastRcvd += (status[fd].isFirstDataWriteRcvd == TRUE) ? i - 1 : i;
					socket.lastRcvd %= SOCKET_BUFFER_SIZE;
					socket.nextExpected = tcpRcvd->seq + 1;
					status[fd].toReceive += tcpRcvd->ad_win;
					call SocketMap.update((uint32_t) fd, socket);
			  		
			  		status[fd].isFirstDataWriteRcvd = FALSE;
			  		printSocketReceiveBuffer(fd);
			  		
//			  		printf("Sending ACK to %d:%d for sequence %d\n", myMsg->src, tcpRcvd->src_port, tcpRcvd->seq);
			  		makeTCPPack(&tcpSend, tcpRcvd->dest_port, tcpRcvd->src_port, status[fd].seq++, tcpRcvd->seq, 0x02, advertisedWindow, NULL, 0);
			  		makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, 0, &tcpSend, PACKET_MAX_PAYLOAD_SIZE);
			  		status[fd].lastAckSent = sendPackage;
					call Sender.send(sendPackage, call Routing.getNextHopTo(sendPackage.dest));
					
				} else if(tcpRcvd->seq < socket.nextExpected) {
//					printf("Resending ACK to %d:%d for sequence %d\n", myMsg->src, tcpRcvd->src_port, socket.nextExpected - 1);
					makeTCPPack(&tcpSend, tcpRcvd->dest_port, tcpRcvd->src_port, 0, socket.nextExpected - 1, 0x02, socket.effectiveWindow, NULL, 0);
			  		makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, 0, &tcpSend, PACKET_MAX_PAYLOAD_SIZE);
					call Sender.send(sendPackage, call Routing.getNextHopTo(sendPackage.dest));
					
				} //else printf("Expected sequence %d.. dropping packet\n", socket.nextExpected);
				
			}
			else if(socket.state == SYN_RCVD) {
				//Client trying to send data when the connection is still only half open, last ack of handshake has been lost.
				//Establishing the connection but not buffering data or sending an ack
				socket.state = ESTABLISHED;
		  		socket.dest.addr = myMsg->src;
		  		socket.dest.port = tcpRcvd->src_port;
		  		socket.nextExpected = status[fd].isn + 2;	//sequence number should be isn+2 after the handshake
		  		
		  		dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to ESTABLISHED\n", fd);

				//Remove entry for this packet in Unacked
				if((i = getUnacked(myMsg)) != -1) call Unacked.remove(i);
				
		  		//Connection established (server)
		  		signal Transport.acceptDone(fd);
				
			} else printf("Socket %d not expecting data\n", fd);
			
			call SocketMap.update((uint32_t) fd, socket);
			break;
		}
	}

   event void SendTimer.fired() {
		tcp_pack sendTCP;
		pack		sendPack;   	
   	socket_t fd;
   	socket_store_t socket;
   	uint8_t i, j, totalSize, sendSize, numSockets = call SocketList.size();
   	uint8_t windowSize = TCP_MAX_PAYLOAD_SIZE * SOCKET_BUFFER_WINDOW_SIZE;
   	uint32_t* keys = call SocketMap.getKeys();
   	uint8_t tempBuff[SOCKET_BUFFER_SIZE] = {0};
   	int8_t nextSend;
   	
   	printf("\n(%d) Transport Send Timer Fired!\n", TOS_NODE_ID);
   	
   	for(i = 0; i < numSockets; i++) {
   		//Grab a socket
   		fd = (socket_t) keys[i];
   		socket = call Transport.getSocket(fd);
   		
   		//Get the total number of values that need to be sent
   		totalSize = status[fd].toSend;
//   		printf("(%d) %d total to send\n", socket.src, totalSize);

   		if(totalSize > 0) {
   		
   			(totalSize > TCP_MAX_PAYLOAD_SIZE) ? (sendSize = TCP_MAX_PAYLOAD_SIZE) : (sendSize = totalSize);
   			if(sendSize > socket.effectiveWindow) sendSize = socket.effectiveWindow; 
   			
   			if(sendSize == 0) {
   				printf("Socket %d waiting for receiver to have available buffer space\n", fd);
   				continue;
   			}
   			
//	   		printf("\t\t(%d:%d) Sending %d bytes to address: %d, port: %d with sequence %d\n", 
//	   					TOS_NODE_ID, socket.src, sendSize, socket.dest.addr, socket.dest.port, status[fd].seq);
				
				//Get the location of the next byte to send
				nextSend = (status[fd].isFirstDataReadSend == TRUE) ? socket.lastSent : socket.lastSent + 1;
				
				//Fill a temporary buffer instead of directly passing &socket.sendBuff[socket.lastSent] to
				//TCPMakePack() due to possible buffer wrap around
				for(j = 0; j < sendSize; j++) {
					if(nextSend + j >= SOCKET_BUFFER_SIZE) nextSend = -j; //If buffer wraps, continue reading from index 0
					tempBuff[j] = socket.sendBuff[nextSend + j];
//					printf("%c ", tempBuff[j]);
					if(socket.sendBuff[j] == 110 && socket.sendBuff[j-1] == 92 && socket.sendBuff[j-2] == 114 && socket.sendBuff[j-3] == 92) {
//						printf("End of command");
						break;
					}
				}
//	   		printf("\n");
				sendSize = j;
	   		
	   		
	   		
   			makeTCPPack(&sendTCP, socket.src, socket.dest.port, status[fd].seq++, 0, 0x00, sendSize, &tempBuff, sendSize);
   			
   			//Set the location of the last byte being sent				
   			socket.lastSent += (status[fd].isFirstDataReadSend == TRUE) ? sendSize - 1 : sendSize;
   			socket.lastSent %= SOCKET_BUFFER_SIZE;
   			//Change some status
   			status[fd].toSend -= sendSize;
   			if(sendSize > 0) status[fd].isFirstDataReadSend = FALSE;
   			
//   			printf("\t %d bytes left in buffer window\n", totalSize - sendSize);
   			
   			call SocketMap.update((uint32_t) fd, socket);
   			
   			printSocketSendBuffer(fd);
   			printSocketReceiveBuffer(fd);
   			
   			makePack(&sendPack, TOS_NODE_ID, socket.dest.addr, MAX_TTL, PROTOCOL_TCP, 0, &sendTCP, PACKET_MAX_PAYLOAD_SIZE);
   			call Sender.send(sendPack, call Routing.getNextHopTo(sendPack.dest));
   			sendPack.TTL = fd;
   			call Unacked.pushback(sendPack);
   			addToUnacked(fd, sendPack);
//   			printUnacked();
   			
   			call Timeout.startPeriodic(800000);
   		}
   		else {
//   			printf("\tSocket %d has no data to send\n", fd);
   			continue;
   		}
   	}
   }

   event void Timeout.fired() {
		uint8_t i, size = call Unacked.size();
		tcp_pack* tcp;
		pack unacked;
		
//		printf("(%d) Timeout! Resend expired unacked packets\n", TOS_NODE_ID);
		
		for(i = 0; i < size; i++) {
			unacked = call Unacked.get(i);
			tcp = (tcp_pack*) &unacked.payload;
			printf("(%d) Resending unacked packet to %d:%d with sequence number %d\n", TOS_NODE_ID, unacked.dest, tcp->dest_port, tcp->seq);
			unacked.TTL = MAX_TTL;
			call Sender.send(unacked, call Routing.getNextHopTo(unacked.dest));
		}
   }	
	
	command socket_t Transport.getSocketFd(uint8_t port) {
   	socket_t fd;
   	socket_store_t socket;
   	uint16_t size = call SocketList.size();
   	uint8_t i;
   	
   	for(i = 0; i < size; i++) {
   		fd = call SocketList.get(i);
   		socket = call SocketMap.get((uint32_t) fd);
   		if(socket.src == port) {
   			return fd;
   		}
   	}
   	return NULL;
   }
	
	socket_t getSocketByDest(uint8_t addr, uint8_t port) {
   	socket_t fd;
   	socket_store_t socket;
   	uint16_t size = call SocketList.size();
   	uint8_t i;
   	
   	for(i = 0; i < size; i++) {
   		fd = call SocketList.get(i);
   		socket = call SocketMap.get((uint32_t) fd);
   		if(socket.dest.addr == addr && socket.dest.port == port) {
   			return fd;
   		}
   	}
   	return NULL;
   }
   
   //TODO: Add checks for valid file descriptor
   command socket_store_t Transport.getSocket(socket_t fd) {
   	return call SocketMap.get((uint32_t) fd);
   }
   
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
   
   void makeTCPPack(tcp_pack *Package, uint8_t src, uint8_t dest, uint8_t seq, uint8_t ack,
   								 uint8_t flags, uint8_t ad_win, uint8_t* payload, uint8_t length) {
   	Package->src_port = src;
   	Package->dest_port = dest;
   	Package->seq = seq;
   	Package->ack = ack;
   	Package->flags = flags;
   	Package->ad_win = ad_win;
   	memcpy(Package->payload, payload, length);
   }
   
   void initSocket(socket_store_t* socket, enum socket_state state, socket_port_t port) {
   	uint8_t i;
   	socket->flag = 0;
   	socket->state = state;
		socket->src = port;
		socket->lastWritten = 0;
		socket->lastAck = 0;
		socket->lastSent = 0;
		socket->lastRead = 0;
		socket->lastRcvd = 0;
		socket->nextExpected = 0;
		socket->RTT = 0;
		socket->effectiveWindow = TCP_MAX_PAYLOAD_SIZE * SOCKET_BUFFER_WINDOW_SIZE;
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			socket->sendBuff[i] = 0;
			socket->rcvdBuff[i] = 0;
		}
   }
   
   socket_t getSocketByDestination(socket_addr_t dest) {
   	socket_t fd;
   	socket_store_t socket;
   	uint16_t size = call SocketList.size();
   	uint8_t i;
   	
   	for(i = 0; i < size; i++) {
   		fd = call SocketList.get(i);
   		socket = call SocketMap.get((uint32_t) fd);
   		if(socket.dest.addr == dest.addr && socket.dest.port == dest.port) {
   			return fd;
   		}
   	}
   	return 0;
   }
     
   void printSockets() {
   	socket_t socket;
   	uint16_t size = call SocketList.size();
   	uint8_t i;
   	
   	printf("Sockets:\n");
   	for(i = 0; i < size; i++) {
   		socket = call SocketList.get(i);
   		printf("\t%d\n", socket);
   	}
   	
   }
   
   void printSocketStates() {
   	socket_store_t store;

		uint32_t* keys = call SocketMap.getKeys();
		uint16_t size = call SocketMap.size();
		uint8_t i;
		
		printf("Node %d socket list: \n", TOS_NODE_ID);
		for(i = 0; i < size; i++) {
			store = call SocketMap.get(keys[i]);
			printf("\tSocket %d: state %d, src_port %d, dest_addr %d, dest_port %d\n", keys[i], store.state, store.src, 
						store.dest.addr, store.dest.port);
		}
		
   }
   
   void printSocketSendBuffer(socket_t fd) {
   	socket_store_t socket = call SocketMap.get((uint32_t) fd);
		uint8_t i;
		
		printf("\n(%d) Socket %d send buffer:\n", TOS_NODE_ID, fd);
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			printf("%c ", (char*)socket.sendBuff[i]);
		}
		printf("\nlastWritten(%d), lastSent(%d), lastAck(%d)\n\n", socket.lastWritten, socket.lastSent, socket.lastAck);
   }
   
   void printSocketReceiveBuffer(socket_t fd) {
		socket_store_t socket = call SocketMap.get((uint32_t) fd);
		uint8_t i;
		
		printf("\n(%d) Socket %d receive buffer:\n", TOS_NODE_ID, fd);
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			printf("%c ", (char*)socket.rcvdBuff[i]);
		}
		printf("\nlastRcvd(%d), lastRead(%d), nextExpected(%d)\n\n", socket.lastRcvd, socket.lastRead, socket.nextExpected);
		
	}
   
   void removeFromSocketList(socket_t fd) {
   	uint16_t size = call SocketList.size();
   	uint8_t i;
   	socket_t socket;
   	
   	for(i = 0; i < size; i++) {
   		socket = call SocketList.get(i);
   		if(socket == fd) {
   			call SocketList.remove(i);
   		}
   	}
   }
   
   socket_t isPendingConnection(connection_t conn) {
   	uint8_t i, size = call ConnectList.size();
   	connection_t pending;
   	
   	for(i = 0; i < size; i++) {
   		pending = call ConnectList.get(i);
   		if(pending.dest.addr == conn.dest.addr && pending.dest.port == conn.dest.port && pending.isn == conn.isn) {
   			return getSocketByDestination(pending.dest);
   		}
   	}
   	
   	return 0;
   }
   
   int8_t getUnacked(pack* packet) {
   	tcp_pack *tcpUnacked, *tcp = (tcp_pack*) packet->payload;
   	uint8_t i, size = call Unacked.size();
   	pack unacked;
   	
   	for(i = 0; i < size; i++) {
			unacked = call Unacked.get(i);
			tcpUnacked = (tcp_pack*) &unacked.payload;
			if(unacked.dest == packet->src && tcpUnacked->src_port == tcp->dest_port && tcpUnacked->seq == tcp->ack) {
				return i;
			}
   	}
   	
   	return -1; 
   }
   
   bool isValidSequence(socket_t fd, uint16_t seq) {
   	uint8_t indexOfSequence = sequenceToIndex(fd, seq);   	
   	socket_store_t socket = call SocketMap.get((uint32_t) fd);
   	
   	//Window wraps buffer
   	if(socket.lastRead > status[fd].endOfWindow) {
   		if(indexOfSequence > socket.lastRead || indexOfSequence <= status[fd].endOfWindow) {
   			return TRUE;
   		}
   	}
   	//Window does not wrap buffer
   	else {
   		if(indexOfSequence > socket.lastRead && indexOfSequence <= status[fd].endOfWindow) {
   			return TRUE;
   		}
   	}
   	
   	return FALSE;
   }
   
   uint8_t sequenceToIndex(socket_t fd, uint16_t seq) {
   	uint8_t dataSequence = seq - status[fd].isn - 1;
		return (((TCP_MAX_PAYLOAD_SIZE - 1) * dataSequence) + (dataSequence - 1)) % SOCKET_BUFFER_SIZE;
	}
	
	void cleanUnacked(socket_t fd, uint16_t seq) {
		uint8_t i = 0;
		tcp_pack *tcpUnacked;
   	pack unacked;
		
		while(i < call Unacked.size()) {
			unacked = call Unacked.get(i);
			tcpUnacked = (tcp_pack*) &unacked.payload;
			if(unacked.TTL == fd && tcpUnacked->seq <= seq) {
				call Unacked.remove(i);
			}
			else i++;
		}
		
	}
	
	void emptyUnacked(socket_t fd) {
		uint8_t i = 0;
		tcp_pack *tcpUnacked;
   	pack unacked;
		
		while(i < call Unacked.size()) {
			unacked = call Unacked.get(i);
			tcpUnacked = (tcp_pack*) &unacked.payload;
			if(unacked.TTL == fd) {
				call Unacked.remove(i);
			}
			else i++;
		}
	}
	
	void addToUnacked(socket_t fd, pack p) {
		uint8_t size = status[fd].unackedSize;
		if(size >= SOCKET_BUFFER_WINDOW_SIZE) {
//			printf("Unacked list full\n");
			return;
		}
	
		status[fd].unackedList[size] = p;
		status[fd].unackedSize++;
	}

	void removeFromUnacked(socket_t fd, uint8_t seq) {
		uint8_t i, j, size = status[fd].unackedSize;
		tcp_pack *tcp;
		pack packet;
		pack temp;
		
		for(i = 0; i < size; i++) {
			packet = status[fd].unackedList[i];
			tcp = (tcp_pack*) packet.payload;
			if(tcp->seq == seq) {
				for(j = i; j < size - 1; j++) {
					status[fd].unackedList[j] = status[fd].unackedList[j+1];
				}
				status[fd].unackedSize--;
				return;
			}
		}
	}

	void removeLessThanSeqFromUnacked(socket_t fd, uint8_t seq) {
		uint8_t i, size = status[fd].unackedSize;
		for(i = 0; i < size; i++) {
			removeFromUnacked(fd, seq--);
		}
	}
	
	
	void printUnacked() {
		uint8_t i, size = call Unacked.size();
		pack unacked;
		tcp_pack *tcp;
		
		printf("Unacked: ");
		for(i = 0; i < size; i++) {
			unacked = call Unacked.get(i);
			tcp = (tcp_pack*) unacked.payload;
			printf("%d ", tcp->seq);
		}
		printf("\n");
	}
	
}
