// Compile/link check only. This executable is never run by CI.
#include <RakNetworkFactory.h>
#include <RakClientInterface.h>
#include <NetworkTypes.h>
static_assert(sizeof(MessageID) == 1, "Message identifiers must remain 8 bit");
static_assert(sizeof(PlayerIndex) == 2, "Player indices must remain 16 bit");
static_assert(sizeof(RakNetTime) == 4, "Legacy timestamps must remain 32 bit");
int main() {
    auto* client = RakNetworkFactory::GetRakClientInterface();
    RakNetworkFactory::DestroyRakClientInterface(client);
    return 0;
}
