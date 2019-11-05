#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module NeighborDiscoveryP {
	//Provides interface NeighborDiscovery to discover neighbors
	provides interface NeighborDiscovery;
	
	//Uses interface SimpleSend to send packets for neighbor discovery
	uses interface SimpleSend as Sender;
	//Uses interface Receive to receive packets
	uses interface Receive as Receiver;
	//Uses interface List to keep a list of neighbors
	uses interface List<neighbor> as NeighborList;
	//Uses interface Timer to periodically run neighbor discovery
	uses interface Timer<TMilli> as discoveryTimer;
}
implementation {
	pack discoveryPackage;
	uint8_t neighbors[17]; //Maximum of 18 neighbors?
		
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	//List helper function prototypes
	bool isNeighbor(uint8_t nodeid);
	error_t addAsNeighbor(uint8_t nodeid);
	void refreshNeighbor(uint8_t nodeid);
	void updateNeighborList();
	void printNeighbors();
	void swapNeighbors(uint8_t, uint8_t);
	void sortNeighborList();					//Insertion sort

	command void NeighborDiscovery.run() {
		//dbg(GENERAL_CHANNEL, "Starting neighbor discovery!\n");
		call discoveryTimer.startPeriodic(1024);
	}
	
	command void NeighborDiscovery.print() {
		printNeighbors();
	}
	
	command uint8_t NeighborDiscovery.getNumNeighbors() {
		return call NeighborList.size();
	}
	
	command uint8_t* NeighborDiscovery.getNeighbors() {
		//First zero out neighbors array
		uint8_t i, size = call NeighborList.size();
		neighbor node;
		
		for(i = 0; i < 17; i++) {
			neighbors[i] = 0;
		}
		
		//Then populate based on NeighborList
		for(i = 0; i < size; i++) {
			node = call NeighborList.get(i);
			neighbors[i] = node.id;
		}
		
		sortNeighborList();
		
		return neighbors;
	}
	
	event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) {
		//If a packet is received, then it came from a neighbor.
		if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         
         //dbg(GENERAL_CHANNEL, "Package recieved\n");
         if(myMsg->protocol == PROTOCOL_DISCOVER) {
		      //If sender already in NeighborList, drop packet
		      if(isNeighbor(myMsg->src)){
		      	//dbg(NEIGHBOR_CHANNEL, "Node %d already in NeighborList\n", myMsg->src);
		      	refreshNeighbor(myMsg->src);
		      	return msg;
		      }
		      //Add the source to NeighborList
		      else {
		      	//dbg(NEIGHBOR_CHANNEL, "Adding node %d to NeighborList\n", myMsg->src);
		      	addAsNeighbor(myMsg->src);
		      }
		      //Send back to neighbor 
		      myMsg->dest = myMsg->src;        
		      myMsg->src = TOS_NODE_ID;
		      
		      call Sender.send(*myMsg, myMsg->dest);
         }
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;	
	}
	
	event void discoveryTimer.fired() {
		//dbg(NEIGHBOR_CHANNEL, "Discovering neighbors!\n");
		updateNeighborList();
		makePack(&discoveryPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_DISCOVER, 0, "Hey neighbor!", PACKET_MAX_PAYLOAD_SIZE);
		//Broadcast to neighbors
		call Sender.send(discoveryPackage, discoveryPackage.dest);
	}
	
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
	
	bool isNeighbor(uint8_t nodeid) {
		uint16_t size = call NeighborList.size();
		uint8_t i;
		neighbor node;
		
		if(!call NeighborList.isEmpty()) {
			for(i = 0; i < size; i++) {
				node = call NeighborList.get(i);
				if(node.id == nodeid) {
					return TRUE;
				}
			}
		}
		return FALSE;
	}
	
	error_t addAsNeighbor(uint8_t nodeid) {	
		uint16_t size = call NeighborList.size();
		uint16_t maxSize = call NeighborList.maxSize();
				
		neighbor node;
		
		if(isNeighbor(nodeid)) {
			return EALREADY;
		}
		
		node.id = nodeid;
		node.TTL = MAX_TTL;
		
		//dbg(NEIGHBOR_CHANNEL, "Adding node %d with TTL %d\n", node.id, node.TTL);
		
		if(size == maxSize) {
			call NeighborList.popfront();
			call NeighborList.pushback(node);
			return SUCCESS;
		}
		else {
			call NeighborList.pushback(node);
			return SUCCESS;
		}
		return FAIL;
	}
	
	void printNeighbors() {
		uint8_t size = call NeighborList.size();
		uint8_t i;
		neighbor node;
		
		dbg(NEIGHBOR_CHANNEL, "Node %d Neighbor List:\n", TOS_NODE_ID);
		
		for(i = 0; i < size; i++) {
			node = call NeighborList.get(i);
			dbg(NEIGHBOR_CHANNEL, "\t\tNode: %d TTL: %d\n", node.id, node.TTL);
		}
	}
	
	void refreshNeighbor(uint8_t nodeid) {
		uint8_t i, size = call NeighborList.size();
		neighbor node;
	
		if(isNeighbor(nodeid)) {
			for(i = 0; i < size; i++) {
				node = call NeighborList.get(i);
				if(node.id == nodeid) {
					node.TTL = MAX_TTL;
					call NeighborList.remove(i);
					call NeighborList.pushback(node);
					//dbg(NEIGHBOR_CHANNEL, "Refreshing TTL of %d to %d\n", node.id, node.TTL);
				}
			}
		}
	}

	void updateNeighborList() {
		uint8_t i, size = call NeighborList.size();
		neighbor node;
		
		for(i = 0; i < size; i++) {
			node = call NeighborList.get(i);
			node.TTL--;
			//dbg(NEIGHBOR_CHANNEL, "Decrementing TTL of %d to %d\n", node.id, node.TTL);
			call NeighborList.remove(i);
			call NeighborList.pushback(node);
			
			if(node.TTL <= 0 || node.TTL > MAX_TTL) {
				//dbg(NEIGHBOR_CHANNEL, "Node %d timed out of neighor list\n", node.id);
				call NeighborList.remove(i);
				signal NeighborDiscovery.changed(i);
			}
		}
	}
	
	void swapNeighbors(uint8_t a, uint8_t b) {
		uint8_t temp = neighbors[a];
		neighbors[a] = neighbors[b];
		neighbors[b] = temp;
	}

	//Used to sort a nodes neighbor info before flooding LSP
	void sortNeighborList() {
		uint8_t i, j;
		uint8_t numNeighbors = call NeighborList.size();
		
		for(i = 1; i < numNeighbors; i++) {
			j = i;
			
			while(j > 0 && neighbors[j-1] > neighbors[j]) {
				swapNeighbors(j, j-1);
				j--;
			}
		}
	}
}
