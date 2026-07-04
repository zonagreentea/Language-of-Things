%{
/* Protocol Handler - Manages 1-bit protocol implementation */
/* Handles message creation, encoding, and transmission */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_MESSAGES 2048
#define MESSAGE_ID_LENGTH 16
#define MAX_PAYLOAD 256

typedef struct {
    char message_id[MESSAGE_ID_LENGTH];
    int bit_value;          /* 0 or 1 */
    int sequence_num;
    time_t timestamp;
    char source[32];
    char destination[32];
    int message_type;       /* 0=data, 1=control, 2=sync, 3=heartbeat */
    unsigned char payload[MAX_PAYLOAD];
    int payload_size;
    int checksum;
} Message;

typedef struct {
    Message messages[MAX_MESSAGES];
    int message_count;
    int sequence_counter;
    int total_bits_sent;
    int errors_detected;
} ProtocolHandler;

ProtocolHandler* global_protocol = NULL;

void initialize_protocol() {
    if (!global_protocol) {
        global_protocol = (ProtocolHandler*)malloc(sizeof(ProtocolHandler));
        global_protocol->message_count = 0;
        global_protocol->sequence_counter = 0;
        global_protocol->total_bits_sent = 0;
        global_protocol->errors_detected = 0;
        printf("[PROTOCOL] Protocol Handler initialized\n");
    }
}

int calculate_checksum(unsigned char* data, int size) {
    int checksum = 0;
    for (int i = 0; i < size; i++) {
        checksum ^= data[i];
    }
    return checksum;
}

int create_message(const char* msg_id, int bit_val, const char* src, 
                   const char* dst, int msg_type) {
    if (!global_protocol) initialize_protocol();
    if (global_protocol->message_count >= MAX_MESSAGES) {
        printf("[ERROR] Message queue full\n");
        return -1;
    }
    
    Message* msg = &global_protocol->messages[global_protocol->message_count];
    strncpy(msg->message_id, msg_id, MESSAGE_ID_LENGTH - 1);
    msg->bit_value = (bit_val == 0) ? 0 : 1;
    msg->sequence_num = global_protocol->sequence_counter++;
    msg->timestamp = time(NULL);
    strncpy(msg->source, src, 31);
    strncpy(msg->destination, dst, 31);
    msg->message_type = msg_type;
    msg->payload_size = 0;
    msg->checksum = 0;
    
    global_protocol->message_count++;
    global_protocol->total_bits_sent++;
    
    printf("[PROTOCOL] Message created: %s (bit=%d, seq=%d)\n", 
           msg_id, bit_val, msg->sequence_num);
    return global_protocol->message_count - 1;
}

void print_message(int index) {
    if (!global_protocol || index >= global_protocol->message_count) return;
    
    Message* msg = &global_protocol->messages[index];
    const char* type_str = (msg->message_type == 0) ? "DATA" :
                           (msg->message_type == 1) ? "CONTROL" :
                           (msg->message_type == 2) ? "SYNC" : "HEARTBEAT";
    
    printf("\n[MESSAGE] ID: %s | Bit: %d | Seq: %d | Type: %s\n", 
           msg->message_id, msg->bit_value, msg->sequence_num, type_str);
    printf("         From: %s -> To: %s\n", msg->source, msg->destination);
    printf("         Checksum: %d | Payload Size: %d\n", msg->checksum, msg->payload_size);
}

void list_messages() {
    if (!global_protocol) {
        printf("Protocol not initialized\n");
        return;
    }
    printf("\n=== Protocol Messages (Total: %d, Bits Sent: %d) ===\n", 
           global_protocol->message_count, global_protocol->total_bits_sent);
    for (int i = 0; i < global_protocol->message_count && i < 10; i++) {
        print_message(i);
    }
    printf("\n");
}
%}

MSG_ID       [A-Za-z0-9]{16}
BIT_VALUE    [0-1]
DEVICE_ID    [A-Fa-f0-9]{32}
MSG_TYPE     (DATA|CONTROL|SYNC|HEARTBEAT)

%%

"INIT" {
    initialize_protocol();
}

"SEND"\s+{MSG_ID}\s+{BIT_VALUE}\s+{DEVICE_ID}\s+{DEVICE_ID}\s+{MSG_TYPE} {
    char msg_id[MESSAGE_ID_LENGTH];
    int bit_val;
    char source[32];
    char dest[32];
    char type_str[16];
    int msg_type = 0;
    
    sscanf(yytext, "SEND %s %d %s %s %s", msg_id, &bit_val, source, dest, type_str);
    
    if (strcmp(type_str, "DATA") == 0) msg_type = 0;
    else if (strcmp(type_str, "CONTROL") == 0) msg_type = 1;
    else if (strcmp(type_str, "SYNC") == 0) msg_type = 2;
    else if (strcmp(type_str, "HEARTBEAT") == 0) msg_type = 3;
    
    create_message(msg_id, bit_val, source, dest, msg_type);
}

"SHOW"\s+[0-9]+ {
    int idx;
    sscanf(yytext, "SHOW %d", &idx);
    print_message(idx);
}

"LIST" {
    list_messages();
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    initialize_protocol();
    yylex();
    return 0;
}
