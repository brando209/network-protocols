interface NeighborDiscovery {
	command void run();
	command void print();
	command uint8_t getNumNeighbors();
	command uint8_t* getNeighbors();
	event void changed(uint8_t id);
}
