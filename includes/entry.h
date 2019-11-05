#ifndef ENTRY_H
#define ENTRY_H

typedef nx_struct RouteEntry{
	nx_uint8_t dest;
	nx_uint8_t cost;
	nx_uint8_t next_hop;
}RouteEntry;

#endif /* ENTRY_H */
