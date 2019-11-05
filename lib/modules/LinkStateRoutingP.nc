#include <../../includes/entry.h>

module LinkStateRoutingP {
	//Provides this to offer link state routing 
	provides interface LinkStateRouting;
	
	//Uses this to get neighbor information
	uses interface NeighborDiscovery;
	//Uses this to flood LSPs
	uses interface SimpleSend as LSPFlooder;
	//Uses this to receive LSP packets
	uses interface Receive as Receiver;
	//Uses this to store the LSPs received, also acts as an adjacency list
	uses interface List<LSP> as LinkStateInfo;
	//Used for Dijkstras Forward Learning algorithm
	uses {
		interface List<RouteEntry> as Confirmed;
		interface List<RouteEntry> as Tentative;
	}
	//Uses this to store the routing table
	uses interface Hashmap<RouteEntry> as RoutingTable;
	uses interface Timer<TMilli> as RoutingTimer;
}
implementation {
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
	//List helper function prototypes
	void floodLSP();
	error_t addLSP(LSP);
	void swapLSP(uint8_t, uint8_t);
	bool isUpdatedLSP(LSP);
	void updateLSP(LSP);
	bool isInLinkStateInfo(LSP);
	uint8_t getPos(uint8_t);
	void sortLinkStateInfo();		//Insertion sort
	void printLinkStateInfo();
	uint8_t getPos(uint8_t id);
	bool inConfirmed(uint8_t);
	bool inTentative(uint8_t);
	uint8_t minInTentative();
	void clearConfirmed();
	void dijkstraForwardSearch();
	void updateRoutingTable();
	void printRoutingTable();
	void updateAges();
	
	command void LinkStateRouting.run() {
		floodLSP();
		call RoutingTimer.startOneShot(1024*8);
	}

	command void LinkStateRouting.print() {
		//Print out all of the link state advertisements used to compute the routing table
		printLinkStateInfo();
		//Print out the routing table
		printRoutingTable();
	}
	
	command uint8_t LinkStateRouting.getNextHopTo(uint8_t dest) {
		RouteEntry entry = call RoutingTable.get(dest);
		return entry.next_hop; 
	}

	event void RoutingTimer.fired() {
		dijkstraForwardSearch();
		updateAges();
	}

	event void NeighborDiscovery.changed(uint8_t id) {
		//Neighbor state has changed
		floodLSP();
	}

	event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) { 
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
			LSP* receivedLSP = (LSP*) myMsg->payload;
			LSP lsp = *receivedLSP;

         //Populate LinkStateInfo list using the LSPs receieved
         if(myMsg->protocol == PROTOCOL_LINKSTATE) {
				//If LSP received is already in LinkStateInfo
				if( isInLinkStateInfo(lsp) ) {
				
					//Check if LSP received is different than one in LinkStateInfo
					if( isUpdatedLSP(lsp) ) //If so then update it
						updateLSP(lsp);
					else return msg;
					
				} else addLSP(lsp); //If not, then add it to LinkStateInfo
				
				//Keep this list sorted
				sortLinkStateInfo();
			}
         
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
	}

	//Generates a LSP, encapsulates it into a pack, and floods it on the network
	void floodLSP() {
		LSP myLSP;
		pack myPack;
		
		//Get a list of current neighbors
		uint8_t i, numNeighbors = call NeighborDiscovery.getNumNeighbors(); 
		uint8_t *neighbors = call NeighborDiscovery.getNeighbors();
		
		//Encapsulate this list into a LSP
		myLSP.numNeighbors = numNeighbors;
		myLSP.id = TOS_NODE_ID;
		for(i = 0; i < numNeighbors; i++) {
			myLSP.neighbors[i] = neighbors[i];
		}
		myLSP.age = 5;
	
		//dbg(FLOODING_CHANNEL, "Flooding LSP\n", TOS_NODE_ID);
	
		//Encapsulate this LSP into a pack struct
		makePack(&myPack, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_LINKSTATE, 0, &myLSP, PACKET_MAX_PAYLOAD_SIZE);
		//Flood this pack on the network
		call LSPFlooder.send(myPack, myPack.dest);
	}

	//Adds a LSP to LinkStateInfo
	error_t addLSP(LSP lsp) {	
		uint16_t size = call LinkStateInfo.size();
		uint16_t maxSize = call LinkStateInfo.maxSize();
		
		if(isInLinkStateInfo(lsp)) {
			return EALREADY;
		}
		
		if(size == maxSize) {
			call LinkStateInfo.popfront();
			call LinkStateInfo.pushback(lsp);
			return SUCCESS;
		}
		else {
			call LinkStateInfo.pushback(lsp);
			return SUCCESS;
		}

		return FAIL;
	}
	
	//Swaps the two LSP entries at position 'a' and 'b' in LinkStateInfo
	void swapLSP(uint8_t a, uint8_t b) {
		LSP lspa = call LinkStateInfo.get(a);
		LSP lspb = call LinkStateInfo.get(b);
		
		LSP temp = lspa;
		call LinkStateInfo.replace(a, lspb);
		call LinkStateInfo.replace(b, temp);
	}
	
	//Determines if 'lsp' is different from the entry in LinkStateInfo with the same id
	bool isUpdatedLSP(LSP lsp) {
		uint8_t i, pos = getPos(lsp.id);
		LSP comp = call LinkStateInfo.get(pos);
		
		if(lsp.numNeighbors == comp.numNeighbors) {
			for(i = 0; i < comp.numNeighbors; i++) {
				if(lsp.neighbors[i] != comp.neighbors[i])
					return TRUE;
			}
			return FALSE;
		}
		return TRUE;
	}
	
	//Updates the LSP with the same id as 'lsp' to 'lsp'
	void updateLSP(LSP lsp) {
		uint8_t pos = getPos(lsp.id);
		
		call LinkStateInfo.replace(pos, lsp);
	}
	
	//Determines if a LSP with id matching that of 'lsp' is in LinkStateInfo
	bool isInLinkStateInfo(LSP lsp) {
		uint16_t size = call LinkStateInfo.size();
		uint8_t i;
		LSP comp;

		if(!call LinkStateInfo.isEmpty()) {
			for(i = 0; i < size; i++) {
				comp = call LinkStateInfo.get(i);
				if(comp.id == lsp.id) {
					return TRUE;
				}
			}
		}
		return FALSE;
	}

	//Sorts the contents of LinkStateInfo
	void sortLinkStateInfo() {
		uint8_t i, j, size = call LinkStateInfo.size();
		LSP a, b;
	
		for(i = 1; i < size; i++) {
			j = i;
						
			a = call LinkStateInfo.get(j-1);
			b = call LinkStateInfo.get(j);
			
			while(j > 0 && a.id > b.id) {
				swapLSP(j-1, j);
				j--;
				
				if(j > 0) {
					a = call LinkStateInfo.get(j-1);
					b = call LinkStateInfo.get(j);
				}
			}
		}
	}
	
	//Prints contents of LinkStateInfo
	void printLinkStateInfo() {
		uint8_t size = call LinkStateInfo.size();
		uint8_t i, j;
		LSP lsp;
		
		dbg(FLOODING_CHANNEL, "Node %d Link State Info(%d entries):\n", TOS_NODE_ID, size);
		
		for(i = 0; i < size; i++) {
			lsp = call LinkStateInfo.get(i);
			printf("\t\t\t\tNode %2d sent [ ", lsp.id);
			for(j = 0; j < lsp.numNeighbors; j++) {
				printf("%2d ", lsp.neighbors[j]);
			}
			printf("]\n");
		}
	}
	
	//Prints contents of Tentative
	void printTentative() {
		uint8_t i, size = call Tentative.size();
		RouteEntry entry;
		printf("Tentative: ");
		for(i = 0; i < size; i++) {
			entry = call Tentative.get(i);
			printf("(%d, %d, %d)", entry.dest, entry.cost, entry.next_hop);
		}
		printf("\n");
	}
	
	//Prints contents of Confirmed
	void printConfirmed() {
		uint8_t i, size = call Confirmed.size();
		RouteEntry entry;
		dbg(FLOODING_CHANNEL, "\n");
		printf("Confirmed: ");
		for(i = 0; i < size; i++) {
			entry = call Confirmed.get(i);
			printf("(%d, %d, %d)", entry.dest, entry.cost, entry.next_hop);
		}
		printf("\n");
	}
	
	//Returns the position of node 'id's LSP in LinkStateInfo
	uint8_t getPos(uint8_t id) {
		uint8_t pos, size = call LinkStateInfo.size();
		LSP lsp;
		
		for(pos = 0; pos < size; pos++) {
			lsp = call LinkStateInfo.get(pos);
			if(id == lsp.id) {
				return pos;
			}
		}
		return 0;
	}

	//Determines if node 'nodeid' is in Confirmed	
	bool inConfirmed(uint8_t nodeid) {
		RouteEntry entry;
		uint8_t i, size = call Confirmed.size();
		
		for(i = 0; i < size; i++) {
			entry = call Confirmed.get(i);
			if(entry.dest == nodeid) {
				return TRUE;
			}
		}
		return FALSE;
	}
	
	//Determines if node 'nodeid' is in Tentative
	bool inTentative(uint8_t nodeid) {
		RouteEntry entry;
		uint8_t i, size = call Tentative.size();
		
		for(i = 0; i < size; i++) {
			entry = call Tentative.get(i);
			if(entry.dest == nodeid) {
				return TRUE;
			}
		}
		return FALSE;
	}
	
	//Returns the position of node 'nodeid' in Tentative
	uint8_t posInTentative(uint8_t nodeid) {
		RouteEntry entry;
		uint8_t i, size = call Tentative.size();
		
		for(i = 0; i < size; i++) {
			entry = call Tentative.get(i);
			if(entry.dest == nodeid) {
				return i;
			}
		}
		return 0;
	}
	
	//Returns the index of the entry in Tentative with the minimum cost
	uint8_t minInTentative() {
		uint8_t i, size = call Tentative.size();
		uint8_t minPos = 0;
		RouteEntry entry, minEntry = call Tentative.get(0);
		
		for(i = 1; i < size; i++) {
			entry = call Tentative.get(i);
			if(entry.cost < minEntry.cost) {
				minEntry = entry;
				minPos = i;
			}
		}
		return minPos;
	}
	
	//Removes all entries from Confirmed
	void clearConfirmed() {
		while(!call Confirmed.isEmpty())
			call Confirmed.popfront();
	}
	
	//Determines if node 'id' is directly connected(a next hop)
	bool isNextHop(uint8_t id) {
		uint8_t i, pos = getPos(TOS_NODE_ID);
		LSP lsp = call LinkStateInfo.get(pos);

		for(i = 0; i < lsp.numNeighbors; i++) {
			if(lsp.neighbors[i] == id) {
				return TRUE;
			}
		}
		return FALSE;
	}
	
	//Determines what the next hop should be to reach 'dest'
	uint8_t findNextHopTo(uint8_t dest) {
		uint8_t k, j, size = call Confirmed.size();
		uint8_t pos;
		RouteEntry entry;
		LSP lsp;
		//For each entry in Confirmed
		for(k = 0; k < size; k++) {
			//Search that entrys neigbors for 'dest'
			entry = call Confirmed.get(k);
			pos = getPos(entry.dest);
			lsp = call LinkStateInfo.get(pos);
			
			for(j = 0; j < lsp.numNeighbors; j++) {
				//If found, then return that entrys 'next_hop'
				if(lsp.neighbors[j] == dest) {
					return entry.next_hop;
				}
			}
		}
		return 0;
	}
	
	//Implementation of Dijkstras algorithm to determine shortest path
	void dijkstraForwardSearch() {
		RouteEntry entry, a, b;
		LSP lsp;
		uint8_t pos, tpos, minTentative, nextHop = 0, i;
		
		//Initialize the Confirmed list with an entry for myself, this entry has a cost of 0.
		entry.dest = TOS_NODE_ID;
		entry.cost = 0;
		entry.next_hop = 0; //Since no node id is 0, this value means NONE;
		call Confirmed.pushback(entry);
		
		do {
			//For the node just added to the Confirmed list, get its LSP.
			pos = getPos(entry.dest);
			lsp = call LinkStateInfo.get(pos);
		
			//For each neighbor, calculate the cost to reach this neighbor as the sum of the cost
			//from myself to Next and from Next to Neighbor.
			for(i = 0; i < lsp.numNeighbors; i++) {
				a.dest = lsp.neighbors[i];
				a.cost = entry.cost + 1;
				
				if(isNextHop(a.dest)) {
					nextHop = a.dest;
				}
				else {
					nextHop = findNextHopTo(a.dest);
				}
				
				a.next_hop = nextHop;
				
				//If Neighbor is currently on neither the Confirmed nor the Tentative list, then add (Neighbor, Cost, NextHop) to the
				//Tentative list, where NextHop is the direction I go to reach Next.
				if(!inTentative(a.dest) && !inConfirmed(a.dest)) {
					call Tentative.pushback(a);
				}
				//If Neighbor is currently on the Tentative list, and the Cost is less than the currently listed cost for Neighbor, 
				//then replace the current entry with new entry
				else if(inTentative(a.dest)) {
					tpos = posInTentative(a.dest);
					b = call Tentative.get(tpos);
					if(a.cost < b.cost) {
						b.cost = a.cost;
						call Tentative.replace(tpos, b);
					}
				}
			}
			//Get the entry off Tentative with the smallest cost and move it to Confirmed
			minTentative = minInTentative();
			entry = call Tentative.get(minTentative);
			call Tentative.remove(minTentative);
			call Confirmed.pushback(entry);
		//If Confirmed has an entry for all nodes on the network(that it has an LSP from), done. Otherwise iterate
		} while( call Confirmed.size() < call LinkStateInfo.size() );
		
		//Move entries from Confirmed to RoutingTable
		updateRoutingTable();
		//Empty Confirmed for the next run of this algorithm
		clearConfirmed();
	}

	//Updates RoutingTable with entries from Confirmed and removes outdated entries
	void updateRoutingTable() {
		uint8_t i, j, size = call Confirmed.size();
		RouteEntry entry;
		uint32_t *keys;
		
		for(i = 0; i < size; i++) {
			entry = call Confirmed.get(i);
			call RoutingTable.insert(entry.dest, entry);
		}
		
		//Cleanup
		keys = call RoutingTable.getKeys();
		for(i = 0; i < call RoutingTable.size(); i++) {
			entry = call RoutingTable.get(keys[i]);
			if(!inConfirmed(entry.dest)) {
				call RoutingTable.remove(keys[i]);
			}
		}
		
	}
	
	//Prints the contents of RoutingTable
	void printRoutingTable() {
		uint8_t i, size = call RoutingTable.size();
		RouteEntry entry;
		
		uint32_t *keys = call RoutingTable.getKeys();
		
		printf("\n\t\t\t    Routing Table for node %d\n", TOS_NODE_ID);
		
		for(i = 0; i < size; i++) {
			entry = call RoutingTable.get(keys[i]);
			printf("\t\t\t\t(%d, %d, %d)\n", entry.dest, entry.cost, entry.next_hop);
		}
	}
	
	//Decrements the age field of all LSP entries in LinkStateInfo and removes if age reaches 0
	void updateAges() {
		uint8_t i, size = call LinkStateInfo.size();
		LSP lsp;
		
		for(i = 0; i < size; i++) {
			lsp = call LinkStateInfo.get(i);
			if(lsp.age <= 1 || lsp.age > 5) {
				call LinkStateInfo.remove(i);
			}
			else {
				lsp.age--;
				call LinkStateInfo.replace(i, lsp);
			}
		}
	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
