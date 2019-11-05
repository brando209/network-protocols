interface Application {
	command error_t startAppServer(uint8_t port);
	command error_t startAppClient(uint8_t port, uint8_t* username);
	command error_t broadcast(uint8_t *message);
	command error_t unicast(uint8_t* username, uint8_t* message);
	command error_t listUsers();
	command error_t receive(pack* message);
}

