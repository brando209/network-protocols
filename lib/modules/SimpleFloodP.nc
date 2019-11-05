#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

/*
*	A node's SimpleSend interface connects to the SimpleSend interface
*	that this module provides(Flooder). If a node calls the send that this  
*	module provides, it will flood the packet out of all of its
*	links (using AM_BROADCAST_ADDR). 
*/

module SimpleFloodP{
	//Provides the SimpleSend interface in order to flood packets
	provides interface SimpleSend as Flooder;
	
	//Uses the SimpleSend interface to forward recieved packet as broadcast
	uses interface SimpleSend as Sender;
	//Uses the Receive interface to determine if received packet is meant for me.
	uses interface Receive as Receiver;
	//Uses the Queue interface to determine if packet recieved has been seen before
	uses interface List<pack> as KnownList;
}
implementation {	
	//List helper function prototypes
	bool isInList(pack packet);
	error_t addToList(pack packet);
	void printList();

	//Broadcast packet
	command error_t Flooder.send(pack msg, uint16_t dest) { 			
		//Attempt to send the packet		
		if( call Sender.send(msg, AM_BROADCAST_ADDR) == SUCCESS ) {
			return SUCCESS;
		}
		return FAIL;				
	}

	//Event signaled when a node recieves a packet
	event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) {
      
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         pack pkt = *myMsg;	//Used to pass into the list helper functions above
         
         //dbg(FLOODING_CHANNEL, "Packet received. Source: %d Destination: %d.\n", myMsg->src, myMsg->dest);
         
         //If I am the original sender or have seen the packet before, drop it
         if((myMsg->src == TOS_NODE_ID) || isInList(pkt)) {
         	//dbg(FLOODING_CHANNEL, "Dropping packet.\n");
         	return msg;
         }
             		
     		//If I am the intended receiver, read packet. Send a reply to original sender
     		if(myMsg->dest == TOS_NODE_ID) {
	         //Note that we have seen this packet.. not needed
	         addToList(pkt);
	         //If packet is a ping reply, done
	         if(myMsg->protocol == PROTOCOL_PINGREPLY) {
	         	dbg(FLOODING_CHANNEL, "Received ACK from %d\n", myMsg->src);
	         	return msg;
	         }
	         else {	//else send a ping reply
	         	dbg(FLOODING_CHANNEL, "Received package from %d\n", myMsg->src);
	        		dbg(FLOODING_CHANNEL, "Package Payload: %s\n", myMsg->payload);
	         
		         myMsg->dest = myMsg->src;
		         myMsg->src = TOS_NODE_ID;
		         myMsg->protocol = PROTOCOL_PINGREPLY;
		         
		         call Flooder.send(*myMsg, myMsg->dest);
				}
	         return msg;
	      }
	      //If not meant for me and hasnt been dropped, forward packet
	      else {
				//dbg(FLOODING_CHANNEL, "Packet not for me.\n");
	      	//dbg(FLOODING_CHANNEL, "Packet not known, adding to list.\n");
	      	addToList(pkt);
	      	
	      	//dbg(FLOODING_CHANNEL, "Forwarding packet.\n");
	      	call Flooder.send(*myMsg, myMsg->dest); 
	      }
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;		
	}
	
	
	//Function to check if packet matches a packet in KnownList
	bool isInList(pack packet) {
		uint16_t size = call KnownList.size();
		uint8_t i;
		pack pkt;
		
		if(!call KnownList.isEmpty()) {
			for(i = 0; i < size; i++) {
				pkt = call KnownList.get(i);
				if(packet.src == pkt.src && packet.seq == pkt.seq) {
					return TRUE;
				}
			}
		}
		return FALSE;
	}
	
	//Function to add packet to KnownList. If the list is full the last element is
	//removed and the new packet added. Does not check if already in list.
	error_t addToList(pack packet) {
		uint16_t size = call KnownList.size();
		uint16_t maxSize = call KnownList.maxSize();
		
		if(size == maxSize) {
			call KnownList.popfront();
			call KnownList.pushback(packet);
			return SUCCESS;
		}
		else {
			call KnownList.pushback(packet);
			return SUCCESS;
		}
		return FAIL;
	}
	
	//Function to print the source and sequence number of the packets in KnownList
	void printList() {
		uint16_t size = call KnownList.size();
		uint8_t i;
		pack pkt;
		
		for(i = 0; i < size; i++) {
			pkt = call KnownList.get(i);
			dbg(FLOODING_CHANNEL, "\t\t%d.) Src: %d Seq: %d\n", i, pkt.src, pkt.seq);
		}
	}
}
