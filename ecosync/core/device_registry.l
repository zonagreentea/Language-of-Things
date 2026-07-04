%{
/* Device Registry - Central device management and discovery */
/* Manages all connected IoT devices in the Ecosync network */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_DEVICES 1024
#define DEVICE_ID_LENGTH 32
#define MAX_DEVICE_NAME 128

typedef struct {
    char device_id[DEVICE_ID_LENGTH];
    char device_name[MAX_DEVICE_NAME];
    char ip_address[16];
    int port;
    int status;           /* 0=offline, 1=online, 2=connecting */
    time_t last_seen;
    int bit_state;        /* 1-bit runtime state: 0 or 1 */
    int device_type;      /* 0=sensor, 1=actuator, 2=hub */
    int signal_strength;  /* 0-100 */
} Device;

typedef struct {
    Device devices[MAX_DEVICES];
    int device_count;
    int registry_id;
    time_t created_at;
} DeviceRegistry;

DeviceRegistry* global_registry = NULL;

void initialize_registry() {
    if (!global_registry) {
        global_registry = (DeviceRegistry*)malloc(sizeof(DeviceRegistry));
        global_registry->device_count = 0;
        global_registry->registry_id = 1;
        global_registry->created_at = time(NULL);
        printf("[REGISTRY] Device Registry initialized\n");
    }
}

int register_device(const char* device_id, const char* name, const char* ip, int port, int device_type) {
    if (!global_registry) initialize_registry();
    if (global_registry->device_count >= MAX_DEVICES) {
        printf("[ERROR] Device registry full\n");
        return -1;
    }
    
    Device* dev = &global_registry->devices[global_registry->device_count];
    strncpy(dev->device_id, device_id, DEVICE_ID_LENGTH - 1);
    strncpy(dev->device_name, name, MAX_DEVICE_NAME - 1);
    strncpy(dev->ip_address, ip, 15);
    dev->port = port;
    dev->status = 1;        /* online */
    dev->last_seen = time(NULL);
    dev->bit_state = 0;
    dev->device_type = device_type;
    dev->signal_strength = 100;
    
    global_registry->device_count++;
    printf("[REGISTRY] Device registered: %s (%s)\n", name, device_id);
    return global_registry->device_count - 1;
}

Device* get_device(const char* device_id) {
    if (!global_registry) return NULL;
    for (int i = 0; i < global_registry->device_count; i++) {
        if (strcmp(global_registry->devices[i].device_id, device_id) == 0) {
            return &global_registry->devices[i];
        }
    }
    return NULL;
}

int update_device_status(const char* device_id, int status) {
    Device* dev = get_device(device_id);
    if (dev) {
        dev->status = status;
        dev->last_seen = time(NULL);
        return 1;
    }
    return 0;
}

int get_device_count() {
    return global_registry ? global_registry->device_count : 0;
}

int get_online_device_count() {
    if (!global_registry) return 0;
    int count = 0;
    for (int i = 0; i < global_registry->device_count; i++) {
        if (global_registry->devices[i].status == 1) count++;
    }
    return count;
}

void list_all_devices() {
    if (!global_registry) {
        printf("Registry not initialized\n");
        return;
    }
    printf("\n=== Device Registry (Total: %d, Online: %d) ===\n", 
           global_registry->device_count, get_online_device_count());
    for (int i = 0; i < global_registry->device_count; i++) {
        Device* dev = &global_registry->devices[i];
        const char* status_str = (dev->status == 0) ? "OFFLINE" : 
                                 (dev->status == 1) ? "ONLINE" : "CONNECTING";
        const char* type_str = (dev->device_type == 0) ? "SENSOR" :
                              (dev->device_type == 1) ? "ACTUATOR" : "HUB";
        printf("[%d] %s | ID: %s | IP: %s:%d | Status: %s | Type: %s | Signal: %d%%\n",
               i, dev->device_name, dev->device_id, dev->ip_address, 
               dev->port, status_str, type_str, dev->signal_strength);
    }
    printf("\n");
}
%}

DEVICE_ID    [A-Fa-f0-9]{32}
IPADDRESS    [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}
PORT         [0-9]{1,5}
NAME         [a-zA-Z0-9_-]+
DEVICE_TYPE  (SENSOR|ACTUATOR|HUB)

%%

"INIT" {
    initialize_registry();
}

"REGISTER"\s+{DEVICE_ID}\s+{NAME}\s+{IPADDRESS}\s+{PORT}\s+{DEVICE_TYPE} {
    char device_id[DEVICE_ID_LENGTH];
    char name[MAX_DEVICE_NAME];
    char ip[16];
    int port;
    char type_str[16];
    int device_type = 0;
    
    sscanf(yytext, "REGISTER %s %s %s %d %s", device_id, name, ip, &port, type_str);
    
    if (strcmp(type_str, "SENSOR") == 0) device_type = 0;
    else if (strcmp(type_str, "ACTUATOR") == 0) device_type = 1;
    else if (strcmp(type_str, "HUB") == 0) device_type = 2;
    
    register_device(device_id, name, ip, port, device_type);
}

"QUERY"\s+{DEVICE_ID} {
    char device_id[DEVICE_ID_LENGTH];
    sscanf(yytext, "QUERY %s", device_id);
    Device* dev = get_device(device_id);
    if (dev) {
        printf("[FOUND] Device: %s at %s:%d (Status: %s)\n", 
               dev->device_name, dev->ip_address, dev->port,
               (dev->status == 1) ? "ONLINE" : "OFFLINE");
    } else {
        printf("[NOT FOUND] Device ID: %s\n", device_id);
    }
}

"LIST" {
    list_all_devices();
}

"COUNT" {
    printf("[STATS] Total devices: %d, Online: %d\n", 
           get_device_count(), get_online_device_count());
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    initialize_registry();
    yylex();
    return 0;
}
