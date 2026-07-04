%{
/* Helper Functions and Utilities */
/* Common functions for Ecosync ecosystem */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

char* get_status_string(int status) {
    switch (status) {
        case 0: return "OFFLINE";
        case 1: return "ONLINE";
        case 2: return "CONNECTING";
        case 3: return "ERROR";
        default: return "UNKNOWN";
    }
}

char* get_message_type_string(int type) {
    switch (type) {
        case 0: return "DATA";
        case 1: return "CONTROL";
        case 2: return "SYNC";
        case 3: return "HEARTBEAT";
        default: return "UNKNOWN";
    }
}

char* get_timestamp_string() {
    static char buffer[26];
    time_t now = time(NULL);
    ctime_r(&now, buffer);
    return buffer;
}

int validate_device_id(const char* device_id) {
    if (!device_id || strlen(device_id) != 32) return 0;
    for (int i = 0; i < 32; i++) {
        char c = device_id[i];
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) {
            return 0;
        }
    }
    return 1;
}

int validate_ip_address(const char* ip) {
    if (!ip) return 0;
    int a, b, c, d;
    if (sscanf(ip, "%d.%d.%d.%d", &a, &b, &c, &d) == 4) {
        return (a >= 0 && a <= 255 && b >= 0 && b <= 255 && 
                c >= 0 && c <= 255 && d >= 0 && d <= 255);
    }
    return 0;
}

void print_system_info() {
    printf("\n=== Ecosync System Information ===\n");
    printf("System Name: Ecosync Multi-Device Network\n");
    printf("Version: 1.0.0\n");
    printf("Protocol: Language-of-Things 1-bit Runtime\n");
    printf("Timestamp: %s", get_timestamp_string());
    printf("\n");
}
%}

%%

"STATUS" {
    printf("[SYSTEM] Status: OPERATIONAL\n");
    printf("[SYSTEM] Timestamp: %s", get_timestamp_string());
}

"VERSION" {
    print_system_info();
}

"HELP" {
    printf("\n=== Ecosync Commands ===\n");
    printf("Device Registry Commands:\n");
    printf("  REGISTER <id> <name> <ip> <port> <type> - Register device\n");
    printf("  QUERY <device_id> - Query device info\n");
    printf("  LIST - List all devices\n");
    printf("\nConnection Manager Commands:\n");
    printf("  CREATE <conn_id> <source> <target> - Create connection\n");
    printf("  OPEN <conn_id> - Open connection\n");
    printf("  CLOSE <conn_id> - Close connection\n");
    printf("\nProtocol Commands:\n");
    printf("  SEND <msg_id> <bit> <src> <dst> <type> - Send message\n");
    printf("\nDiscovery Commands:\n");
    printf("  DISCOVER <disc_id> <device_id> <range> - Start discovery\n");
    printf("  PROBE - Probe network\n");
    printf("\n");
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    printf("Ecosync - Language-of-Things Ecosystem\n");
    yylex();
    return 0;
}
