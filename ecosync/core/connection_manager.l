%{
/* Connection Manager - Handles device-to-device connections */
/* Manages connection lifecycle and 1-bit channel state */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_CONNECTIONS 512
#define CONNECTION_ID_LENGTH 16
#define MAX_BUFFER_SIZE 4096

typedef struct {
    char connection_id[CONNECTION_ID_LENGTH];
    char source_device[32];
    char target_device[32];
    int connection_state;    /* 0=closed, 1=open, 2=pending, 3=error */
    int bit_channel;         /* 1-bit channel state */
    int error_count;
    time_t created_at;
    time_t last_activity;
    int packets_sent;
    int packets_received;
    int bandwidth_usage;     /* percentage 0-100 */
} Connection;

typedef struct {
    Connection connections[MAX_CONNECTIONS];
    int connection_count;
    int total_packets;
} ConnectionManager;

ConnectionManager* global_conn_manager = NULL;

void initialize_connection_manager() {
    if (!global_conn_manager) {
        global_conn_manager = (ConnectionManager*)malloc(sizeof(ConnectionManager));
        global_conn_manager->connection_count = 0;
        global_conn_manager->total_packets = 0;
        printf("[CONN_MGR] Connection Manager initialized\n");
    }
}

int create_connection(const char* conn_id, const char* source, const char* target) {
    if (!global_conn_manager) initialize_connection_manager();
    if (global_conn_manager->connection_count >= MAX_CONNECTIONS) {
        printf("[ERROR] Connection pool exhausted\n");
        return -1;
    }
    
    Connection* conn = &global_conn_manager->connections[global_conn_manager->connection_count];
    strncpy(conn->connection_id, conn_id, CONNECTION_ID_LENGTH - 1);
    strncpy(conn->source_device, source, 31);
    strncpy(conn->target_device, target, 31);
    conn->connection_state = 2;  /* pending */
    conn->bit_channel = 0;
    conn->error_count = 0;
    conn->created_at = time(NULL);
    conn->last_activity = time(NULL);
    conn->packets_sent = 0;
    conn->packets_received = 0;
    conn->bandwidth_usage = 0;
    
    global_conn_manager->connection_count++;
    printf("[CONN_MGR] Connection created: %s\n", conn_id);
    return global_conn_manager->connection_count - 1;
}

int open_connection(const char* conn_id) {
    if (!global_conn_manager) return 0;
    for (int i = 0; i < global_conn_manager->connection_count; i++) {
        if (strcmp(global_conn_manager->connections[i].connection_id, conn_id) == 0) {
            global_conn_manager->connections[i].connection_state = 1;
            global_conn_manager->connections[i].last_activity = time(NULL);
            printf("[CONN_MGR] Connection opened: %s\n", conn_id);
            return 1;
        }
    }
    return 0;
}

int close_connection(const char* conn_id) {
    if (!global_conn_manager) return 0;
    for (int i = 0; i < global_conn_manager->connection_count; i++) {
        if (strcmp(global_conn_manager->connections[i].connection_id, conn_id) == 0) {
            global_conn_manager->connections[i].connection_state = 0;
            printf("[CONN_MGR] Connection closed: %s\n", conn_id);
            return 1;
        }
    }
    return 0;
}

void list_connections() {
    if (!global_conn_manager) {
        printf("Connection Manager not initialized\n");
        return;
    }
    printf("\n=== Active Connections (Total: %d) ===\n", global_conn_manager->connection_count);
    for (int i = 0; i < global_conn_manager->connection_count; i++) {
        Connection* conn = &global_conn_manager->connections[i];
        const char* state_str = (conn->connection_state == 0) ? "CLOSED" :
                                (conn->connection_state == 1) ? "OPEN" :
                                (conn->connection_state == 2) ? "PENDING" : "ERROR";
        printf("[%d] %s | %s -> %s | State: %s | Bit: %d | Packets: %d sent, %d rcvd\n",
               i, conn->connection_id, conn->source_device, conn->target_device,
               state_str, conn->bit_channel, conn->packets_sent, conn->packets_received);
    }
    printf("\n");
}
%}

CONN_ID      [A-Za-z0-9]{16}
DEVICE_ID    [A-Fa-f0-9]{32}

%%

"INIT" {
    initialize_connection_manager();
}

"CREATE"\s+{CONN_ID}\s+{DEVICE_ID}\s+{DEVICE_ID} {
    char conn_id[CONNECTION_ID_LENGTH];
    char source[32];
    char target[32];
    
    sscanf(yytext, "CREATE %s %s %s", conn_id, source, target);
    create_connection(conn_id, source, target);
}

"OPEN"\s+{CONN_ID} {
    char conn_id[CONNECTION_ID_LENGTH];
    sscanf(yytext, "OPEN %s", conn_id);
    open_connection(conn_id);
}

"CLOSE"\s+{CONN_ID} {
    char conn_id[CONNECTION_ID_LENGTH];
    sscanf(yytext, "CLOSE %s", conn_id);
    close_connection(conn_id);
}

"LIST" {
    list_connections();
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    initialize_connection_manager();
    yylex();
    return 0;
}
