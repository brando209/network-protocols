/**
 * @author UCM ANDES Lab
 * $Author: abeltran2 $
 * $LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
 *
 */


#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

module CommandHandlerP{
   provides interface CommandHandler;
   uses interface Receive;
   uses interface Pool<message_t>;
   uses interface Queue<message_t*>;
   uses interface Packet;
}

implementation{
	uint8_t extractWord(char* string, char* word);

    task void processCommand(){
        if(! call Queue.empty()){
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;
            
            char commandString[3][32] = {{0}};
			uint8_t commandLength = 0;
			
            // Pop message out of queue.
            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            // Check to see if the packet is valid.
            if(!payload){
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }
            // Change it to our type.
            msg = (CommandMsg*) payload;

            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;

            //Find out which command was called and call related command
            switch(commandID){
            // A ping will have the destination of the packet as the first
            // value and the string in the remainder of the payload
            case CMD_PING:
                dbg(COMMAND_CHANNEL, "Command Type: Ping\n");
                signal CommandHandler.ping(buff[0], &buff[1]);
                break;

            case CMD_NEIGHBOR_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
                signal CommandHandler.printNeighbors();
                break;

            case CMD_LINKSTATE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
                signal CommandHandler.printLinkState();
                break;

            case CMD_ROUTETABLE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
                signal CommandHandler.printRouteTable();
                break;
				//A test client command will have a destination as the first valve, 
				//a source port and a destination port as the next two values
				//and a transfer size(in bytes) as the next value
            case CMD_TEST_CLIENT:
                dbg(COMMAND_CHANNEL, "Command Type: Test Client\n");
                signal CommandHandler.setTestClient(buff[0], buff[1], buff[2], buff[3]);
                break;
				//A test server command will have a port number as the only value
            case CMD_TEST_SERVER:
                dbg(COMMAND_CHANNEL, "Command Type: Test Server\n");
                signal CommandHandler.setTestServer(buff[0]);
                break;
            case CMD_APP_CLIENT:
            	dbg(COMMAND_CHANNEL, "Command Type: App Client\n");
            	commandLength = extractWord(buff, commandString[0]);
            	if(strcmp(commandString[0], "hello") == 0) {
            		commandLength += extractWord(&buff[commandLength], commandString[1]);	//Extract username
            		commandLength += extractWord(&buff[commandLength], commandString[2]);	//Extract port
            		printf("%s %s %d\n", commandString[0], commandString[1], atoi(commandString[2]));
            		signal CommandHandler.setAppClient(atoi(commandString[2]), (uint8_t*)commandString[1]);
            	}
            	else if(strcmp(commandString[0], "msg") == 0) {
            		printf("%s %s\n", commandString[0], &buff[commandLength+1]);
            		signal CommandHandler.broadcastAppClient(&buff[commandLength]);
            	}
            	else if(strcmp(commandString[0], "whisper") == 0) {
            		commandLength += extractWord(&buff[commandLength], commandString[1]); 	//Extract username
            		printf("%s %s %s\n", commandString[0], commandString[1], &buff[commandLength]);
            		signal CommandHandler.unicastAppClient(&commandString[1], &buff[commandLength]);
            	}
            	else if(strcmp(commandString[0], "listusr") == 0) {
            		signal CommandHandler.listAppUsers();
            	}
            	break;
            case CMD_APP_SERVER:
            	dbg(COMMAND_CHANNEL, "Command Type: App Server\n");
            	signal CommandHandler.setAppServer(buff[0]);
            	break;
				//A close connection command will have a destinationn address as the first
				//value, a source port as the second, and a destination port as the third
			case CMD_KILL:
				dbg(COMMAND_CHANNEL, "Command Type: Close Connenction\n");
				signal CommandHandler.closeTestClient(buff[0], buff[1], buff[2]);
				break;	
            default:
                dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                break;
            }
            call Pool.put(raw_msg);
        }

        if(! call Queue.empty()){
            post processCommand();
        }
    }
    
    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len){
        if (! call Pool.empty()){
            call Queue.enqueue(raw_msg);
            post processCommand();
            return call Pool.get();
        }
        return raw_msg;
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
}
