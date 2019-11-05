/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/socket.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;
	uses interface SimpleSend as Flooder;
	
	uses interface NeighborDiscovery;
	uses interface LinkStateRouting;
	uses interface Transport;

   uses interface CommandHandler;
   
   uses interface Application;
   
   uses interface Timer<TMilli> as RoutingTimer;
   uses interface Timer<TMilli> as ClientWriteTimer;
   uses interface Timer<TMilli> as ServerAcceptTimer;
   
   uses interface List<socket_t> as ServerConnections;
   uses interface List<socket_t> as ClientConnections;
}
implementation{
   pack sendPackage;
	buffer_t globalBuffer[MAX_NUM_OF_SOCKETS]; //Global buffer variable(one buffer per connection)
	
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void initGlobalBuffers();
	//uint8_t fillBuffer(uint16_t* buff, uint8_t size, uint16_t start);
	uint8_t fillBuffer(uint16_t *buff, uint8_t pos, uint8_t size, uint16_t nextVal);
   void readBuffer(uint16_t *buff, uint8_t loc, uint8_t size);
   void printGlobalBuffer(socket_t fd);
	uint16_t min(uint16_t a, uint16_t b);
   
   event void Boot.booted(){
      call AMControl.start();
		initGlobalBuffers();
      dbg(GENERAL_CHANNEL, "Booted\n");
   }
   
   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
      call NeighborDiscovery.run();
      call RoutingTimer.startPeriodic(1024*8);
   }

   event void AMControl.stopDone(error_t err){}
   
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         tcp_pack* myTCPRecv = (tcp_pack*) myMsg->payload;
         tcp_pack  myTCPSend;
         uint8_t nextHop;
         
         if(myMsg->protocol == PROTOCOL_PING || myMsg->protocol == PROTOCOL_TCP) {	
		      if(myMsg->dest == AM_BROADCAST_ADDR) {	
		      	dbg(GENERAL_CHANNEL, "Package recieved\n");
		      	dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
		      	call Flooder.send(*myMsg, myMsg->dest);
		      }
		      else if(myMsg->dest != TOS_NODE_ID) {
		      	nextHop = call LinkStateRouting.getNextHopTo(myMsg->dest);
		      	dbg(ROUTING_CHANNEL, "Package received for %d. Forwarding to next hop: %d\n", myMsg->dest, nextHop);
		      	call Sender.send(*myMsg, nextHop);
		      }
		      else {
		      	if(myMsg->protocol == PROTOCOL_PING){
		      		dbg(GENERAL_CHANNEL, "Package recieved\n");
	         		dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
		      	}
		      	if(myMsg->protocol == PROTOCOL_TCP) {
		      		call Application.receive(myMsg);
		      	}
		      }
		   }
         
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

	event void RoutingTimer.fired() {
		call LinkStateRouting.run();
	}


	event void ServerAcceptTimer.fired() {
/*		uint8_t i, j, numRead = 0, nextRead, readSize, size = call ServerConnections.size();
		buffer_t* buffer;
		socket_store_t socket, newSocket;
		socket_t fd, newFd;
		
//		printf("\n===============(%d) Server Accept Timer fired===============\n", TOS_NODE_ID);
		
//		printf("Checking sockets for connection requests\n");
		//Go through the list of server connections and check if there are connect requests
		//for the sockets in the LISTEN state
		for(i = 0; i < size; i++) {
			fd = call ServerConnections.get(i);
			socket = call Transport.getSocket(fd);
			if(socket.state == LISTEN) {
				newFd = call Transport.accept(fd);
				//newFd added to ServerConnections when acceptDone is signaled
			}
		}

		//For all sockets in ServerConnections list, read available data from sockets
		//in the ESTABLISHED state and print
		size = call ServerConnections.size();
//		printf("Checking sockets for data to read\n", TOS_NODE_ID);
		
		for(i = 0; i <	size; i++) {
			fd = call ServerConnections.get(i);
			socket = call Transport.getSocket(fd);
			
			if(socket.state != ESTABLISHED) continue;
			
			//Get the position of the next value to read
			nextRead = (socket.lastRead == 0 && socket.rcvdBuff[socket.lastRead] == 1) ? socket.lastRead : socket.lastRead + 1;
			
			buffer = &globalBuffer[fd];

			numRead = call Transport.read(fd, &buffer->buff[nextRead], SOCKET_BUFFER_SIZE);
					
			socket = call Transport.getSocket(fd);
			
			if(numRead > 0) {
//				printGlobalBuffer(fd);
				printf("\n-----------------------------------------------------------------------------------------------------------------------------------------------\n");
				dbg(TRANSPORT_CHANNEL, "(port %d) Reading Data: ", socket.src);
				readBuffer(&buffer->buff[0], nextRead, numRead);
				printf("\n-----------------------------------------------------------------------------------------------------------------------------------------------\n");
			}
		}*/
	}

	event void ClientWriteTimer.fired() {
/*		uint8_t i, nextRead = 0, readSize = 0; //Read from global buffer to socket buffer
		uint8_t numWritten = 0, numToWrite = 0, size = call ClientConnections.size();
		socket_t fd;
		socket_store_t socket;
		buffer_t* buffer;

//		printf("\n===============(%d) Client Write Timer fired================\n", TOS_NODE_ID);
		
		//Write data from buffers to appropriate socket buffers
		for(i = 0; i < size; i++) {
			fd = call ClientConnections.get(i);
			socket = call Transport.getSocket(fd);
			buffer = &globalBuffer[fd];

			//Next value to read out of the global buffer
			nextRead = (buffer->firstWrite == TRUE) ? buffer->lastRead : (buffer->lastRead + 1) % SOCKET_BUFFER_SIZE;
			
			if(buffer->transferSize > 0) {
				//Determine how much data we can write to the global buffer
				if(buffer->firstWrite == TRUE) { 
					numToWrite = SOCKET_BUFFER_SIZE; 
				}
				else if(socket.lastSent + 1 == buffer->currentPosition) {
					numToWrite = 0;
				}
				else if(buffer->currentPosition < socket.lastSent) { 
					numToWrite = socket.lastSent - buffer->currentPosition + 1; 
				}
				else if (buffer->currentPosition > socket.lastSent) {	
					numToWrite = SOCKET_BUFFER_SIZE - buffer->currentPosition + socket.lastSent + 1;
				}
				else {
					printf("Handle exceptional case!!!!!!!\n");
				}
			
				numToWrite = min(buffer->transferSize, numToWrite);
			
//				printGlobalBuffer(fd); printf("\n");
			}
			
			//Write as may values as possible to the global buffer(limited by 
			numWritten = fillBuffer(&buffer->buff[0], buffer->currentPosition, numToWrite, buffer->nextVal);
			
//			printGlobalBuffer(fd); printf("\n");
			
			readSize = call Transport.write(fd, &buffer->buff[nextRead], buffer->sendSize);

			//If values have been written into the global buffer, update the buffers state information
			if(numWritten > 0) {
				buffer->currentPosition += numWritten; 
				buffer->currentPosition %= SOCKET_BUFFER_SIZE;
				
				buffer->lastWritten += (buffer->firstWrite == TRUE) ? numWritten - 1: numWritten;
				buffer->lastWritten %= SOCKET_BUFFER_SIZE;
				
				buffer->transferSize -= numWritten;
				buffer->nextVal += numWritten;
//				printf("%d values written to global buffer %d\n", numWritten, fd);
			}
			
			if(readSize > 0) {
				buffer->sendSize -= readSize;
//				printf("%d values written to socket %d send buffer\n", readSize, fd);
			}

			//Update the value of the last byte read from the global buffer into the socket buffer
			buffer->lastRead += (buffer->firstWrite == TRUE) ? readSize - 1 : readSize;
			buffer->lastRead %= SOCKET_BUFFER_SIZE;
			
			//Must refetch socket to get updated state since write() modified it
			socket = call Transport.getSocket(fd);

			//After the first write is complete, this should always be false
			buffer->firstWrite = FALSE;
		}*/
	}

	event error_t Transport.acceptDone(socket_t fd) {
/*		socket_store_t socket = call Transport.getSocket(fd);
		printf("(%d) Connection Established with address %d, port %d through socket %d, port %d\n", TOS_NODE_ID,
					socket.dest.addr, socket.dest.port, fd, socket.src);
		
		//Push the new connection to the list of server connections
		call ServerConnections.pushback(fd);
		*/
	}

	event error_t Transport.connectDone(socket_t fd) {
/*		socket_store_t socket = call Transport.getSocket(fd);
		printf("(%d) Connection Established with address %d, port %d through socket %d, port %d\n", TOS_NODE_ID,
					socket.dest.addr, socket.dest.port, fd, socket.src);
	
		call ClientConnections.pushback(fd);
		
		//Now we can start writing to the send buffer
		if(!call ClientWriteTimer.isRunning()) {
			call ClientWriteTimer.startPeriodic(1024*256);
		}*/
	}

	event void NeighborDiscovery.changed(uint8_t id) { }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
   	uint8_t nextHop = call LinkStateRouting.getNextHopTo(destination);
      dbg(GENERAL_CHANNEL, "PING EVENT\n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, nextHop);
      //call Flooder.send(sendPackage, destination); //To show packet flooding
   }

   event void CommandHandler.printNeighbors(){
   	call NeighborDiscovery.print();
   }

   event void CommandHandler.printRouteTable(){
   	call LinkStateRouting.print();
   }

   event void CommandHandler.printLinkState(){
   	call LinkStateRouting.print();
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(uint8_t port){
   	socket_t socket;
   	socket_addr_t address;
		address.port = port;
		address.addr = TOS_NODE_ID;
   	
   	dbg(TRANSPORT_CHANNEL, "Initiating Server at address %d\n", TOS_NODE_ID);
   	
   	//Try to get a new socket
   	socket = call Transport.socket();
   	
   	//If successfully obtained new socket
   	if(socket != NULL) {	
	   	dbg(TRANSPORT_CHANNEL, "Obtained socket: %d\n", socket);
	   	
	   	//Try to bind socket to new address/port
	   	if(call Transport.bind(socket, &address) == SUCCESS) {
	   		dbg(TRANSPORT_CHANNEL, "Binded to address: %d, port: %d\n", address.addr, address.port);	 
	   		  		
   			//If successfully binded socket to new address, attempt to listen on the socket
   		   if(call Transport.listen(socket) == SUCCESS) {
   				dbg(TRANSPORT_CHANNEL, "Changed state of socket %d to LISTEN\n", socket); 
   				
   				//If successful, place the new socket fd in ServerConnections list
   				call ServerConnections.pushback(socket);
   				
   				//Now that we a listening on a socket, start a timer to check for connection attempts
   				if(!call ServerAcceptTimer.isRunning())
   					call ServerAcceptTimer.startPeriodic(1024*300);	
   					
	   		} else printf("Error! Unable to change state to LISTEN\n");
	   		
   		} else printf("Error! Unable to bind socket %d to port: %d\n", socket, address.port);	
   		
   	} else printf("Error! No socket available\n");
   }

   event void CommandHandler.setTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer){
   	socket_t socket;
   	socket_addr_t srcAddr, destAddr;
   	uint8_t i = 0;
   	buffer_t* buffer;
   	
   	dbg(TRANSPORT_CHANNEL, "Initiating Client at address %d\n", TOS_NODE_ID);

   	//Source address, port
   	srcAddr.port = srcPort;
   	srcAddr.addr = TOS_NODE_ID;
   	//Destination address, port
   	destAddr.port = destPort;
   	destAddr.addr = dest;
   	
   	//Try to get a new socket
   	socket = call Transport.socket();
   	//If successfully obtained new socket
   	if(socket != NULL) {
	   	dbg(TRANSPORT_CHANNEL, "Obtained socket: %d\n", socket);
	   	//Try to bind socket to new address/port
	   	if(call Transport.bind(socket, &srcAddr) == SUCCESS) {
				dbg(TRANSPORT_CHANNEL, "Binded to address: %d, port: %d\n", srcAddr.addr, srcAddr.port);
				dbg(TRANSPORT_CHANNEL, "Attempting to connect to server at %d:%d\n", destAddr.addr, destAddr.port);
				//If successfully binded new socket
				if(call Transport.connect(socket, &destAddr) == SUCCESS) {
					//Initialize the global buffer for this socket
					buffer = &globalBuffer[socket];
					buffer->transferSize = 260; //transfer; //TODO: Fix this hard code, this is due to not getting values > 255 from python file
					buffer->sendSize = buffer->transferSize;
					
				} else printf("Error! Unable to attempt a connect to %d:%d\n", destAddr.addr, destAddr.port);
				
			} else printf("Error! Unable to bind socket %d to %d:%d\n", socket, srcAddr.addr, srcAddr.port);
			
   	} else printf("Error! No socket available\n");
   }

	event void CommandHandler.closeTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort) {
		uint8_t fd;
		
		dbg(TRANSPORT_CHANNEL, "Attempting to close connection (src, srcPort, dest, destPort) = (%d, %d, %d, %d)\n", 
				TOS_NODE_ID, srcPort, dest, destPort);	
		
		fd = call Transport.getSocketFd(srcPort);
		if(fd != NULL) {
			if(call Transport.close(fd) == FAIL) {
				printf("Error! Unable to close socket %d\n", fd);
			}
		}
		else {
			printf("Error! Unable to find socket bound to port %d\n", srcPort);
		}
	}

   event void CommandHandler.setAppServer(uint8_t port) {
   	printf("Intiating Chat Server at address %d, port %d\n", TOS_NODE_ID, port);
   	call Application.startAppServer(port);
   }

   event void CommandHandler.setAppClient(uint8_t port, uint8_t* username){
   	char user[128];
   	sprintf(user, "%s", (char*)username);

   	printf("Initiating Chat Client at address %d, port %d\n", TOS_NODE_ID, port);
   	printf("Clients username is '%s'\n", user);
   	printf("Sending command 'hello %s %d' to server\n", user, port);
   	
   	call Application.startAppClient(port, username);
   }
   
   event void CommandHandler.broadcastAppClient(uint8_t* message) {
   	uint8_t i;
   	printf("Broadcasting message: \n");
   	call Application.broadcast(message);
   }

	event void CommandHandler.unicastAppClient(uint8_t* username, uint8_t* message) {
		call Application.unicast(username, message);
	}
	
	event void CommandHandler.listAppUsers() { 
		call Application.listUsers();
	}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

	//Pass the head of the buffer to this function
	void readBuffer(uint16_t *buff, uint8_t loc, uint8_t size) {
		uint8_t i;
		
		for(i = 0; i < size; i++) {
			printf("%hu, ", buff[(loc + i) % SOCKET_BUFFER_SIZE]);
		}
		
	}
	
	uint8_t fillBuffer(uint16_t *buff, uint8_t pos, uint8_t size, uint16_t nextVal) {
		uint8_t count;
		
		for(count = 0; count < size; count++) {
			buff[(pos + count) % SOCKET_BUFFER_SIZE] = nextVal++;
		}
		
		return count;
		
	}

	void printGlobalBuffer(socket_t fd) {
		uint8_t i;
   	buffer_t buffer = globalBuffer[fd];
   	printf("\nSocket %d global buffer:\n", fd);
   	for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
   		printf("%4d ", buffer.buff[i]);
   	}
   	printf("\ncurrentPosition(%d), lastWritten(%d), lastRead(%d), transferSize(%d)\n", 
   		buffer.currentPosition, 
   		buffer.lastWritten, 
   		buffer.lastRead,
   		buffer.transferSize
   	);
	}

	uint16_t min(uint16_t a, uint16_t b) {
		return (a < b) ? a : b;
	}
	
	void initGlobalBuffers() {
		uint8_t i, j;
		for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
			globalBuffer[i].currentPosition = 0;
			globalBuffer[i].lastWritten = 0;
			globalBuffer[i].lastRead = 0;
			globalBuffer[i].transferSize = 0;
			globalBuffer[i].sendSize = 0;
			globalBuffer[i].firstWrite = TRUE;
			globalBuffer[i].nextVal = 1;
			for(j = 0; j < SOCKET_BUFFER_SIZE; j++) {
				globalBuffer[i].buff[j] = 0;
			}
		}
	}
	

	
	
	
	
}
