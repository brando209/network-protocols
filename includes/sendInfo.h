//Author: UCM ANDES Lab
//Date: 2/15/2012
#ifndef PACK_BUFFER_H
#define PACK_BUFFER_H

#include "packet.h"

enum{
	SEND_BUFFER_SIZE=128
};

typedef struct sendInfo{
	pack packet;
	uint16_t src;
	uint16_t dest;
}sendInfo;

typedef struct neighbor {
		uint8_t id;
		uint8_t TTL;
}neighbor;

#endif /* PACK_BUFFER_H */
