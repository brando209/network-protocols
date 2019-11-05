//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


#include "protocol.h"
#include "channels.h"

enum{
	PACKET_HEADER_LENGTH = 8,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
	TCP_HEADER_LENGTH = 6,
	TCP_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - TCP_HEADER_LENGTH,
	MAX_TTL = 15
};


typedef nx_struct pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint16_t seq;		//Sequence Number
	nx_uint8_t TTL;		//Time to Live
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;

//Project 2
typedef nx_struct link_state_pack{
	nx_uint8_t id;
	nx_uint8_t numNeighbors;
	nx_uint8_t age;
	nx_uint8_t neighbors[PACKET_MAX_PAYLOAD_SIZE - 3];
	//costs array corresponding to neighbor links: not needed since assume all links have same cost
}LSP;

//Project 3
typedef nx_struct tcp_pack{
	nx_uint8_t src_port;
	nx_uint8_t dest_port;
	nx_uint8_t seq;
	nx_uint8_t ack;
	nx_uint8_t flags;
	nx_uint8_t ad_win;
	nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE];
}tcp_pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input){
	dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %hhu  Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

enum{
	AM_PACK=6
};

#endif
