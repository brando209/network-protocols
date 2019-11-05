module ApplicationP {
	provides interface Application;
	
	uses interface Transport;
	
	uses interface List<socket_t> as ServerConnections;
	
	uses interface Timer<TMilli> as ServerTimer;
	uses interface Timer<TMilli> as ClientTimer;
}
implementation {
	socket_t clientConnection; //This is the socket file descriptor for the client tcp connection to the server, restrict this to one connection
	buffer_t clientCommandBuffer;		//For client to buffer outgoing commands
	buffer_t clientMessageBuffer;		//For client to buffer received messages
	buffer_t serverCommandBuffers[MAX_NUM_OF_SOCKETS];	//For servers to buffer received commands
	queue_t commands[MAX_NUM_OF_SOCKETS];			//A server queue for received commands
	char usernames[MAX_NUM_OF_SOCKETS][12];		//Assuming size of username < 12 characters
	
	uint8_t extractWord(char* string, char* word);
	uint8_t extractCommand(socket_t fd, buffer_t *buff);
	uint8_t extractMessage(socket_t fd, buffer_t *buffer);
	bool isValidCommand(uint8_t* cmnd);
	bool isValidMessage(uint8_t* cmnd);
	void pushCommand(socket_t fd, uint8_t* cmnd);
	void popCommand(socket_t fd, uint8_t* cmnd);
	void handleCommand(socket_t fd, uint8_t* commandString);
	void addUser(socket_t fd, uint8_t* username);
	void broadcast(uint8_t* message);
	void unicast(uint8_t* username, uint8_t* message);
	void list(socket_t fd);

	void readBuffer(uint8_t *buff, uint8_t loc, uint8_t size);
	void printServerCommandBuffer(socket_t fd);
	void printClientBuffer();
	void initServerBuffers();
	void initClientBuffers();

	command error_t Application.startAppServer(uint8_t port) {
		socket_t socket;
   	socket_addr_t address;
		address.port = port;
		address.addr = TOS_NODE_ID;
   	
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
   				
   				//Now that we are listening on a socket, start a timer to check for connection attempts
   				if(!call ServerTimer.isRunning())
   					call ServerTimer.startPeriodic(1024*300);	
   					
   				initServerBuffers();
   					
   				return SUCCESS;
   					
	   		} else printf("Error! Unable to change state to LISTEN\n");
	   		
   		} else printf("Error! Unable to bind socket %d to port: %d\n", socket, address.port);	
   		
   	} else printf("Error! No socket available\n");
	
		return FAIL;
	}
	
	command error_t Application.startAppClient(uint8_t port, uint8_t* username) {
		socket_t socket;
   	socket_addr_t srcAddr, destAddr;
   	uint8_t i = 0, numWritten = 0;
   	
		uint8_t buff[SOCKET_BUFFER_SIZE];

		//Write 'hello' into the buffer
		sprintf(buff, "hello ");
   	
   	//Source address, port
   	srcAddr.port = port;
   	srcAddr.addr = TOS_NODE_ID;
   	//Destination address, port of well known server
   	destAddr.port = 41;
   	destAddr.addr = 1;
   	
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
					
					initClientBuffers();
					sprintf(buff, "hello %s%c%c%c%c%c", (char*)username, 92, 114, 92, 110, '\0');	//Create the hello command
					numWritten = call Transport.write(socket, buff, strlen((char*)buff));
					//if(numWritten > 0) {
						//clientCommandBuffer.lastRead += (clientCommandBuffer.firstRead == TRUE) ? numWritten - 1: numWritten; 
						//if(clientCommandBuffer.firstRead == TRUE) clientCommandBuffer.firstRead = FALSE;
					//}
											
					call ClientTimer.startPeriodic(1024*300);							//Start a timer to check for messages received
					
					return SUCCESS; 	
										
				} else printf("Error! Unable to attempt a connect to %d:%d\n", destAddr.addr, destAddr.port);
				
			} else printf("Error! Unable to bind socket %d to %d:%d\n", socket, srcAddr.addr, srcAddr.port);
			
   	} else printf("Error! No socket available\n");	
		
		return FAIL;
	}
	
	command error_t Application.broadcast(uint8_t* message) {
		uint8_t numRead = 0, nextRead;
		char msg[SOCKET_BUFFER_SIZE];
		
		//nextRead = (clientCommandBuffer.firstRead == TRUE) ? clientCommandBuffer.lastRead : (clientCommandBuffer.lastRead + 1) % SOCKET_BUFFER_SIZE;
		
		sprintf(msg, "msg %s%c%c%c%c%c", (char*)message, 92, 114, 92, 110, '\0');
		numRead = call Transport.write(clientConnection, msg, strlen((char*) msg));
		//clientCommandBuffer.lastRead += (clientCommandBuffer.firstRead == TRUE) ? numRead - 1: numRead;
		//if(clientCommandBuffer.firstRead == TRUE) clientCommandBuffer.firstRead = FALSE;
	}	
	
	command error_t Application.unicast(uint8_t* username, uint8_t* message) {
		uint8_t numRead = 0, nextRead;
		char msg[SOCKET_BUFFER_SIZE];
		
		//nextRead = (clientCommandBuffer.firstRead == TRUE) ? clientCommandBuffer.lastRead : (clientCommandBuffer.lastRead + 1) % SOCKET_BUFFER_SIZE;
		
		sprintf(msg, "whisper %s %s%c%c%c%c%c", (char*)username, (char*)message, 92, 114, 92, 110, '\0');
		numRead = call Transport.write(clientConnection, msg, strlen((char*) msg));
		//clientCommandBuffer.lastRead += (clientCommandBuffer.firstRead == TRUE) ? numRead - 1: numRead;
		//if(clientCommandBuffer.firstRead == TRUE) clientCommandBuffer.firstRead = FALSE;
	}
	
	command error_t Application.listUsers() {
		uint8_t numRead = 0, nextRead;
		char msg[32];
		
		//nextRead = (clientCommandBuffer.firstRead == TRUE) ? clientCommandBuffer.lastRead : (clientCommandBuffer.lastRead + 1) % SOCKET_BUFFER_SIZE;
		
		sprintf(msg, "listusr%c%c%c%c%c", 92, 114, 92, 110, '\0');
		numRead = call Transport.write(clientConnection, msg, strlen((char*) msg));
		//clientCommandBuffer.lastRead += (clientCommandBuffer.firstRead == TRUE) ? numRead - 1: numRead;
		//if(clientCommandBuffer.firstRead == TRUE) clientCommandBuffer.firstRead = FALSE;
	}
	
	command error_t Application.receive(pack* message) {
		call Transport.receive(message);
	}
	
	event error_t Transport.connectDone(socket_t fd) { 
		socket_store_t socket = call Transport.getSocket(fd);
		printf("(%d) Connection Established with address %d, port %d through socket %d, port %d\n", TOS_NODE_ID,
					socket.dest.addr, socket.dest.port, fd, socket.src);
		
		clientConnection = fd;
		
		return SUCCESS;
	}
	
	event error_t Transport.acceptDone(socket_t fd) {
		socket_store_t socket = call Transport.getSocket(fd);
		printf("(%d) Connection Established with address %d, port %d through socket %d, port %d\n", TOS_NODE_ID,
					socket.dest.addr, socket.dest.port, fd, socket.src);
					
		call ServerConnections.pushback(fd);
		
		return SUCCESS;
	}
	
	event void ServerTimer.fired() {
		uint8_t i, size = call ServerConnections.size();
		buffer_t* buffer;
		socket_store_t socket;
		socket_t fd, newFd;
		uint8_t readLength = 0;
		uint8_t commandLength = 0;
		uint8_t buff[SOCKET_BUFFER_SIZE] = {0};
		
		printf("Checking sockets for connection requests\n");
		//Go through the list of server connections and check if there are connect requests
		//for the sockets in the LISTEN state
		for(i = 0; i < size; i++) {
			fd = call ServerConnections.get(i);
			socket = call Transport.getSocket(fd);
			if(socket.state == LISTEN) {
				newFd = call Transport.accept(fd);
			}
		}
		
		printf("Checking receive buffers for incoming commands\n");
		//Go through the list of server connections and check if there is data to read from the receive buffer
		//If there is, read it from the buffer and pass this to an internal command handler to handle
		for(i = 0; i < size; i++) {
			fd = call ServerConnections.get(i);
			socket = call Transport.getSocket(fd);
			buffer = &serverCommandBuffers[fd];
			if (socket.state == ESTABLISHED) {
				printf("Checking socket %d\n", fd);
				readLength = call Transport.read(fd, &buffer->buff[buffer->currentPosition], SOCKET_BUFFER_SIZE);
			}
			if(readLength > 0) {
				printf("Read %d from socket %d receive buffer at %d\n", readLength, fd, buffer->currentPosition);
				buffer->currentPosition += readLength; 
				buffer->currentPosition %= SOCKET_BUFFER_SIZE;
				buffer->lastWritten += (buffer->firstWrite == TRUE) ? readLength - 1: readLength;
				buffer->lastWritten %= SOCKET_BUFFER_SIZE;
				if(buffer->firstWrite == TRUE) buffer->firstWrite = FALSE;
			}
			
			commandLength = extractCommand(fd, buffer);
			
			if(commandLength > 0) {
				buffer->lastRead += (buffer->firstRead == TRUE) ? commandLength - 1 : commandLength;
				buffer->lastRead %= SOCKET_BUFFER_SIZE;
				if(buffer->firstRead == TRUE) buffer->firstRead = FALSE;
			}
		}
		
		printf("Executing received commands\n");
		for(i = 0; i < size; i++) {
			fd = call ServerConnections.get(i);
			buff[0] = '\0';
			popCommand(fd, buff);
			printf("Socket %d:\n", fd);
			if(strlen((char*) buff) > 0) {
				printf("Executing %s\n", (char*) buff);
				handleCommand(fd, buff);
			}
		}
	}
	
	event void ClientTimer.fired() { 
		socket_store_t socket = call Transport.getSocket(clientConnection);
		uint8_t position = clientMessageBuffer.currentPosition;
		uint8_t messageLength, writeLength, nextRead;
		buffer_t *buffer = &clientMessageBuffer;
		
		printf("(%d) Checking socket for received messages\n", TOS_NODE_ID);
		
		writeLength = call Transport.read(clientConnection, &buffer->buff[position], SOCKET_BUFFER_SIZE);
		printf("Read %d from socket %d receive buffer at %d\n", writeLength, clientConnection, buffer->currentPosition);
		
		if(writeLength > 0) {
			printf("Data being read\n");
			buffer->currentPosition += writeLength; 
			buffer->currentPosition %= SOCKET_BUFFER_SIZE;
			buffer->lastWritten += (buffer->firstWrite == TRUE) ? writeLength - 1: writeLength;
			buffer->lastWritten %= SOCKET_BUFFER_SIZE;
			buffer->firstWrite == FALSE;
			
			printClientBuffer();
		}

		messageLength = extractMessage(clientConnection, buffer);
		
		if(messageLength > 0) {
			nextRead = (buffer->firstRead == TRUE) ? buffer->lastRead : (buffer->lastRead + 1) % SOCKET_BUFFER_SIZE;
			
			printf("\n\n------------------------------------------------------------------------------------------------------------------------\n");
			printf("(%d) ", TOS_NODE_ID);
			readBuffer(buffer, nextRead, messageLength);
			printf("\n------------------------------------------------------------------------------------------------------------------------\n\n");
			
			buffer->lastRead += (buffer->firstRead == TRUE) ? messageLength - 1 : messageLength;
			buffer->lastRead %= SOCKET_BUFFER_SIZE;
			buffer->firstRead = FALSE;
		}
	}

	uint8_t extractMessage(socket_t fd, buffer_t *buffer) {
		uint8_t i, position = (buffer->lastRead + 1) % SOCKET_BUFFER_SIZE;
		char messageBuff[SOCKET_BUFFER_SIZE];
		
		if(buffer->firstRead == TRUE) { 
			position = 0;
		}
		
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			messageBuff[i] = buffer->buff[(position + i) % SOCKET_BUFFER_SIZE];
			if(messageBuff[i] == 110 && messageBuff[i-1] == 92 && messageBuff[i-2] == 114 && messageBuff[i-3] == 92) {
				messageBuff[i+1] = '\0';
				if(isValidMessage(messageBuff)) {
					printf("Extracted message from receive buffer\n");
					printf("\tMessage: %s\n", messageBuff);
					return strlen((char*) messageBuff);
				}
			}
		}

		return 0;
	}

	uint8_t extractCommand(socket_t fd, buffer_t *buffer) {
		uint8_t i, position = (buffer->lastRead + 1) % SOCKET_BUFFER_SIZE;
		char commandBuff[SOCKET_BUFFER_SIZE];
		
		if(buffer->firstRead == TRUE) { position = 0; }
		if(buffer->lastRead == buffer->lastWritten) return 0;
		
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			commandBuff[i] = buffer->buff[(position + i) % SOCKET_BUFFER_SIZE];
			if(commandBuff[i] == 110 && commandBuff[i-1] == 92 && commandBuff[i-2] == 114 && commandBuff[i-3] == 92) {
				commandBuff[i+1] = '\0';
				if(isValidCommand(commandBuff)) {
					pushCommand(fd, commandBuff);
					return strlen((char*) commandBuff);
				}
			}
		}

		return 0;
	}
	
	bool isValidMessage(uint8_t* cmnd) {
		uint8_t offset = 0, word[SOCKET_BUFFER_SIZE];
		
		while(cmnd[offset] != '\0') {
			offset++;
			if(offset >= SOCKET_BUFFER_SIZE) return FALSE;
		}
		
		if(cmnd[offset - 1] == 110 && cmnd[offset - 2] == 92 && cmnd[offset - 3] == 114 && cmnd[offset - 4] == 92) {
			return TRUE;
		}

		return FALSE;
	}
	
	bool isValidCommand(uint8_t* cmnd) {
		uint8_t offset = 0, word[32];
		
		offset += extractWord(cmnd, word);
		if(strcmp((char*) word, "listusr\\r\\n") == 0) { return TRUE; }
		
		if((strcmp((char*) word, "hello") == 0) || (strcmp((char*) word, "msg") == 0) || (strcmp((char*) word, "whisper") == 0)) {
		
			while(cmnd[offset] != '\0') {
				offset++;
			}
			
			if(cmnd[offset - 1] == 110 && cmnd[offset - 2] == 92 && cmnd[offset - 3] == 114 && cmnd[offset - 4] == 92) {
				return TRUE;
			}
		}
		
		return FALSE;
	}
	
	void handleCommand(socket_t fd, uint8_t* commandString) {
		uint8_t j = 0, position;
		char commandBuff[SOCKET_BUFFER_SIZE] = {0};
		char wordBuff[2][SOCKET_BUFFER_SIZE] = {{0}};
		
		printf("Handling command %s, %d\n", (char*)commandString, strlen((char*)commandString));
		
		j += extractWord(commandString, &wordBuff[0]);
		
		if(strcmp(&wordBuff[0], "hello") == 0) {
			j += extractWord(&commandString[j], &wordBuff[1]);
			position = strlen(wordBuff[1]);
			wordBuff[1][position - 4] = '\0';
			addUser(fd, wordBuff[1]);
		}
		else if(strcmp(&wordBuff[0], "msg") == 0) {
			broadcast(&commandString[strlen((char*)wordBuff[0])]);
		}
		else if(strcmp(&wordBuff[0], "whisper") == 0) {
			j += extractWord(&commandString[j], &wordBuff[1]);
			unicast(&wordBuff[1], &commandString[j]);
		}
		else if(strcmp(&wordBuff[0], "listusr\\r\\n") == 0) {
			list(fd);
		}
		else {
			printf("\n\n\n!\n!\n!\nReceived unknown command\n\n!\n!\n!\n");
		}
	}
	
	void addUser(socket_t fd, uint8_t* username) {
		printf("\n\n\n\n\n\nHELLO %s\n\n\n\n\n\n");	
		sprintf(&usernames[fd], "%s", username);
	}
	
	void broadcast(uint8_t* message) {
		uint8_t i, nextRead, numRead, size = call ServerConnections.size();
		socket_t fd;
		uint8_t msg[SOCKET_BUFFER_SIZE];
		
		printf("\n\n\n\n\n\n\nBROADCAST: %s\n\n\n\n\n\n", (char*)message);
		sprintf(msg, "%s", (char*)message);
		
		for(i = 0; i < size; i++) {
			fd = call ServerConnections.get(i);
			if(fd != 1) {
				printf("Preparing to write to socket %d buffer\n", fd);
				numRead = call Transport.write(fd, msg, strlen((char*)msg));
			}
		}
	}
	
	void unicast(uint8_t* username, uint8_t* message) {
		uint8_t i, nextRead, numRead, size = call ServerConnections.size();
		socket_t fd;
		uint8_t msg[SOCKET_BUFFER_SIZE];
		
		
		printf("\n\n\n\n\n\n\n\nUNICAST to %s: %s\n\n\n\n\n\n", (char*)username, (char*)message);
		sprintf(msg, "%s", (char*) message);
		
		for(i = 0; i < size; i++) {
			fd = call ServerConnections.get(i);
			if(strcmp(&usernames[fd], username) == 0) {
				printf("Preparing to write to socket %d buffer\n", fd);
				numRead = call Transport.write(fd, msg, strlen((char*)message));
			}
		}
	}
	
	void list(socket_t fd) {
		uint8_t i, len = 0, size = call ServerConnections.size();
		uint8_t msg[SOCKET_BUFFER_SIZE] = {0};
		uint8_t buff[SOCKET_BUFFER_SIZE] = {0};
		socket_t sendfd;
		
		printf("\n\n\n\n\n\n\n\nPRINT USERS\n\n\n\n\n\n");
		
		for(i = 0; i < size; i++) {
			sendfd = call ServerConnections.get(i);
			if(sendfd == 1) continue;
			
			if(i != size - 1) {
				if(strlen(usernames[sendfd]) == 0) {
					sprintf(&buff[len], "%s, ", "UNKNOWN");
					len += 9;
				} else {
					sprintf(&buff[len], "%s, ", usernames[sendfd]);
					len += strlen((char*) usernames[sendfd]) + 2;
				}
			}
			else {
				if(strlen(usernames[sendfd]) == 0) {
					sprintf(&buff[len], "%s%c%c%c%c%c", "UNKNOWN", 92, 114, 92, 110, '\0');
					len += 9;
				} else {
					sprintf(&buff[len], "%s%c%c%c%c%c", usernames[sendfd], 92, 114, 92, 110, '\0');
					len += strlen((char*) usernames[sendfd]);
				}
			}
		}
		
		sprintf(msg, "listUsrReply: %s", (char*) buff);
		printf("%s\n", msg);
		
		call Transport.write(fd, msg, strlen((char*) msg));
		
	}
	
	uint8_t extractWord(char* string, char* word) {
    	uint8_t count;
    	
 		for(count = 0; TRUE; count++) {
 			if(string[count] == '\0') {
 				word[count] = '\0';
 				break;
 			}
 			 			
 			if(string[count] != ' ') {
 				word[count] = string[count];
 			}
 			else {
 				word[count] = '\0';
 				break;
 			}
 		}
 		
    	return count + 1;
	}
	
	void pushCommand(socket_t fd, uint8_t* cmnd) {
		uint8_t i, back = commands[fd].back;
		uint8_t popped[SOCKET_BUFFER_SIZE] = {0};
		
		sprintf(commands[fd].commands[back], "%s", (char*) cmnd);
		
		commands[fd].back++;
		commands[fd].size++;	
	}
	
	void popCommand(socket_t fd, uint8_t* cmnd) {
		uint8_t length, i;
		
		if(commands[fd].size == 0) return;
		
		length = strlen(&commands[fd].commands[0]);
		
		for(i = 0; i < length; i++) {
			*(cmnd + i) = commands[fd].commands[0][i];
			if(i > 4 && cmnd[i] == 110 && cmnd[i-1] == 92 && cmnd[i-2] == 114 && cmnd[i-3] == 92) {
				cmnd[i + 1] = '\0';
			}
		}

		for(i = 1; i < commands[fd].size; i++) {
			memcpy(commands[fd].commands[i - 1], commands[fd].commands[i], strlen((char*) commands[fd].commands[i]));
		}
		
		commands[fd].size--;
		commands[fd].back--;
	}
	
	void printCommandQueue(socket_t fd) {
		uint8_t i;
		printf("\n\n\n\n\n\nSocket %d command queue: \n", fd);
		for(i = 0; i < commands[fd].back; i++) {
			printf("%s\n", (char*) commands[fd].commands[i]);
		}
		printf("\n\n");
	}

	//Pass the head of the buffer to this function
	void readBuffer(uint8_t *buff, uint8_t loc, uint8_t size) {
		uint8_t i;
		
		for(i = 0; i < size - 4; i++) {
			printf("%c", buff[(loc + i) % SOCKET_BUFFER_SIZE]);
		}
		
	}
	
	void printClientBuffer() {
		uint8_t i;
		printf("\nClient application buffer:\n");
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			printf("%c ", (char)clientCommandBuffer.buff[i]);
		}
		printf("\ncurrentPosition(%d), lastWritten(%d), lastRead(%d)\n", 
   		clientCommandBuffer.currentPosition, 
   		clientCommandBuffer.lastWritten, 
   		clientCommandBuffer.lastRead
   	);
	}

	void printServerCommandBuffer(socket_t fd) {
		uint8_t i;
   	buffer_t buffer = serverCommandBuffers[fd];
   	printf("\nServer(socket %d) command buffer:\n", fd);
   	for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
   		printf("%c ", (char)buffer.buff[i]);
   	}
   	printf("\ncurrentPosition(%d), lastWritten(%d), lastRead(%d)\n", 
   		buffer.currentPosition, 
   		buffer.lastWritten, 
   		buffer.lastRead
   	);
	}
	
	void initClientBuffers() {
		uint8_t i;
		clientCommandBuffer.currentPosition = 0;
		clientCommandBuffer.lastWritten = 0;
		clientCommandBuffer.lastRead = 0;
		clientCommandBuffer.transferSize = 0;
		clientCommandBuffer.sendSize = 0;
		clientCommandBuffer.firstWrite = TRUE;
		clientCommandBuffer.firstRead = TRUE;
		clientCommandBuffer.nextVal = 1;
		clientMessageBuffer.currentPosition = 0;
		clientMessageBuffer.lastWritten = 0;
		clientMessageBuffer.lastRead = 0;
		clientMessageBuffer.transferSize = 0;
		clientMessageBuffer.sendSize = 0;
		clientMessageBuffer.firstWrite = TRUE;
		clientMessageBuffer.firstRead = TRUE;
		clientMessageBuffer.nextVal = 1;
		for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
			clientCommandBuffer.buff[i] = 0;
			clientMessageBuffer.buff[i] = 0;
		}
	}
	
	void initServerBuffers() {
		uint8_t i, j, k;
		queue_t* cmnds;
		
		for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
			serverCommandBuffers[i].currentPosition = 0;
			serverCommandBuffers[i].lastWritten = 0;
			serverCommandBuffers[i].lastRead = 0;
			serverCommandBuffers[i].transferSize = 0;
			serverCommandBuffers[i].sendSize = 0;
			serverCommandBuffers[i].firstWrite = TRUE;
			serverCommandBuffers[i].firstRead = TRUE;
			serverCommandBuffers[i].nextVal = 1;
			cmnds = &commands[i];
			cmnds->front = 0;
			cmnds->back = 0;
			cmnds->size = 0;
			for(j = 0; j < SOCKET_BUFFER_SIZE; j++) {
				serverCommandBuffers[i].buff[j] = 0;
				for(k = 0; k < 10; k++) {
					cmnds->commands[k][j] = 0;
				}
			}
		}
	}

}
