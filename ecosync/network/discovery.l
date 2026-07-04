%{
/* Network Discovery - Device discovery and dynamic registration */
/* Enables automatic device detection in IoT web environment */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_DISCOVERY_REQUESTS 256
#define MAX_DISCOVERED_DEVICES 1024

typedef struct {
    char device_id[32];
    char device_name[128];
    char ip_address[16];
    int port;
    time_t discovered_at;
} DiscoveredDevice;

typedef struct {
    char discovery_id[16];
    char requester[32];
    int discovery_range;   /* network range */
    int devices_found;
    time_t discovery_time;
    int active;            /* 0=completed, 1=active, 2=failed */
} DiscoveryRequest;

typedef struct {
    DiscoveryRequest requests[MAX_DISCOVERY_REQUESTS];
    DiscoveredDevice devices[MAX_DISCOVERED_DEVICES];
    int request_count;
    int device_count;
} DiscoveryEngine;

DiscoveryEngine* global_discovery = NULL;

void initialize_discovery() {
    if (!global_discovery) {
        global_discovery = (DiscoveryEngine*)malloc(sizeof(DiscoveryEngine));
        global_discovery->request_count = 0;
        global_discovery->device_count = 0;
        printf("[DISCOVERY] Network Discovery Engine initialized\n");
    }
}

int start_discovery(const char* discovery_id, const char* requester, int range) {
    if (!global_discovery) initialize_discovery();
    if (global_discovery->request_count >= MAX_DISCOVERY_REQUESTS) {
        printf("[ERROR] Discovery request queue full\n");
        return -1;
    }
    
    DiscoveryRequest* req = &global_discovery->requests[global_discovery->request_count];
    strncpy(req->discovery_id, discovery_id, 15);
    strncpy(req->requester, requester, 31);
    req->discovery_range = range;
    req->devices_found = 0;
    req->discovery_time = time(NULL);
    req->active = 1;
    
    global_discovery->request_count++;
    printf("[DISCOVERY] Discovery started: %s (range: %d)\n", discovery_id, range);
    return global_discovery->request_count - 1;
}

int add_discovered_device(const char* device_id, const char* name, const char* ip, int port) {
    if (!global_discovery) initialize_discovery();
    if (global_discovery->device_count >= MAX_DISCOVERED_DEVICES) {
        printf("[ERROR] Discovery cache full\n");
        return -1;
    }
    
    DiscoveredDevice* dev = &global_discovery->devices[global_discovery->device_count];
    strncpy(dev->device_id, device_id, 31);
    strncpy(dev->device_name, name, 127);
    strncpy(dev->ip_address, ip, 15);
    dev->port = port;
    dev->discovered_at = time(NULL);
    
    global_discovery->device_count++;
    printf("[DISCOVERY] Device discovered: %s (%s:%d)\n", name, ip, port);
    return global_discovery->device_count - 1;
}

void list_discovered() {
    if (!global_discovery) {
        printf("Discovery not initialized\n");
        return;
    }
    printf("\n=== Discovered Devices (Total: %d) ===\n", global_discovery->device_count);
    for (int i = 0; i < global_discovery->device_count; i++) {
        DiscoveredDevice* dev = &global_discovery->devices[i];
        printf("[%d] %s | IP: %s:%d | ID: %s\n",
               i, dev->device_name, dev->ip_address, dev->port, dev->device_id);
    }
    printf("\n");
}
%}

DISC_ID      [A-Za-z0-9]{16}
DEVICE_ID    [A-Fa-f0-9]{32}
RANGE        [0-9]{1,3}
IPADDRESS    [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}
PORT         [0-9]{1,5}
NAME         [a-zA-Z0-9_-]+

%%

"INIT" {
    initialize_discovery();
}

"DISCOVER"\s+{DISC_ID}\s+{DEVICE_ID}\s+{RANGE} {
    char disc_id[16];
    char requester[32];
    int range;
    
    sscanf(yytext, "DISCOVER %s %s %d", disc_id, requester, &range);
    start_discovery(disc_id, requester, range);
}

"ADD"\s+{DEVICE_ID}\s+{NAME}\s+{IPADDRESS}\s+{PORT} {
    char device_id[32];
    char name[128];
    char ip[16];
    int port;
    
    sscanf(yytext, "ADD %s %s %s %d", device_id, name, ip, &port);
    add_discovered_device(device_id, name, ip, port);
}

"PROBE" {
    printf("[DISCOVERY] Probing network for Ecosync devices...\n");
}

"LIST" {
    list_discovered();
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    initialize_discovery();
    yylex();
    return 0;
}
