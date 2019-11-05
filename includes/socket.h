#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
    SOCKET_BUFFER_WINDOW_SIZE = 8,	//Window size cannot be larger than 9
};

enum socket_state{
    CLOSED = 0,
    LISTEN = 1,
    ESTABLISHED = 2,
    SYN_SENT = 3,
    SYN_RCVD = 4,
};

typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;

// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;					//0->brand new socket
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;

    // This is the sender(client) portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;	//Last byte written by the client application
    uint8_t lastAck;			//Last byte that has recieved an ack
    uint8_t lastSent;		//Last byte that has been sent to the server
    
    // This is the receiver(server) portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;		//Last byte read by the server application
    uint8_t lastRcvd;		//Last byte written into the buffer
    uint8_t nextExpected;	//Next expected byte to be recieved, usually lastRcvd+1

    uint16_t RTT;
    uint8_t effectiveWindow;
}socket_store_t;

typedef struct connection_t {
	socket_t fd;
	socket_addr_t src;
	socket_addr_t dest;
	uint16_t isn;
	uint16_t transfer;
}connection_t;

typedef struct buffer_t {
	uint8_t buff[SOCKET_BUFFER_SIZE];
	uint8_t currentPosition;			//Current position
	uint8_t lastWritten;					//Last index written into the buffer
	uint8_t lastRead;						//Last index read from the buffer
	uint16_t nextVal;
	uint16_t transferSize;				//Size of data still needing to be written to buffer
	uint16_t sendSize;					//Size of data still needing to be read from buffer
	bool firstWrite;						//Is this the first time writing into this buffer?
	bool firstRead;
}buffer_t;

typedef struct queue_t {
	uint8_t commands[10][SOCKET_BUFFER_SIZE];
	uint8_t front;
	uint8_t back;
	uint8_t size;
}queue_t;

typedef struct status_t {
	uint8_t isn;
	uint8_t seq;
	
	uint16_t sentTime;
	uint16_t rcvdTime;
	
	uint8_t toSend;
	uint8_t toReceive;

	uint8_t startOfWindow;
	uint8_t endOfWindow;
	
	bool isFirstDataReadSend;
	bool isFirstDataReadRcvd;
	bool isFirstDataWriteSend;
	bool isFirstDataWriteRcvd;
	
	bool isActive;
	
	uint16_t lastAckedSeq;
	
	pack lastAckSent;
	
	pack unackedList[SOCKET_BUFFER_WINDOW_SIZE];
	uint8_t unackedSize;
	
}status_t;

#endif
