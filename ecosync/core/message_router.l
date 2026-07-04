%{
/* Message Router - Routes 1-bit messages across device network */
/* Handles message forwarding and intelligent routing */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_ROUTES 256
#define MAX_MESSAGE_QUEUE 1024

typedef struct {
    char route_id[16];
    char source[32];
    char destination[32];
    char next_hop[32];
    int hops;
    int priority;  /* 0=low, 1=normal, 2=high */
    int active;    /* 0=inactive, 1=active */
    time_t created_at;
} Route;

typedef struct {
    Route routes[MAX_ROUTES];
    int route_count;
    int messages_routed;
} MessageRouter;

MessageRouter* global_router = NULL;

void initialize_router() {
    if (!global_router) {
        global_router = (MessageRouter*)malloc(sizeof(MessageRouter));
        global_router->route_count = 0;
        global_router->messages_routed = 0;
        printf("[ROUTER] Message Router initialized\n");
    }
}

int create_route(const char* route_id, const char* source, const char* dest, 
                 const char* next_hop, int hops, int priority) {
    if (!global_router) initialize_router();
    if (global_router->route_count >= MAX_ROUTES) {
        printf("[ERROR] Route table full\n");
        return -1;
    }
    
    Route* route = &global_router->routes[global_router->route_count];
    strncpy(route->route_id, route_id, 15);
    strncpy(route->source, source, 31);
    strncpy(route->destination, dest, 31);
    strncpy(route->next_hop, next_hop, 31);
    route->hops = hops;
    route->priority = priority;
    route->active = 1;
    route->created_at = time(NULL);
    
    global_router->route_count++;
    printf("[ROUTER] Route created: %s (%d hops)\n", route_id, hops);
    return global_router->route_count - 1;
}

int route_message(const char* source, const char* destination) {
    if (!global_router) initialize_router();
    
    for (int i = 0; i < global_router->route_count; i++) {
        Route* route = &global_router->routes[i];
        if (strcmp(route->source, source) == 0 && 
            strcmp(route->destination, destination) == 0 &&
            route->active) {
            global_router->messages_routed++;
            printf("[ROUTER] Message routed via: %s\n", route->next_hop);
            return 1;
        }
    }
    printf("[ROUTER] No route found\n");
    return 0;
}

void list_routes() {
    if (!global_router) {
        printf("Router not initialized\n");
        return;
    }
    printf("\n=== Routing Table (Total: %d, Routed: %d) ===\n", 
           global_router->route_count, global_router->messages_routed);
    for (int i = 0; i < global_router->route_count; i++) {
        Route* route = &global_router->routes[i];
        const char* priority_str = (route->priority == 0) ? "LOW" :
                                   (route->priority == 1) ? "NORMAL" : "HIGH";
        printf("[%d] %s | %s -> %s | Next: %s | Hops: %d | Priority: %s\n",
               i, route->route_id, route->source, route->destination,
               route->next_hop, route->hops, priority_str);
    }
    printf("\n");
}
%}

ROUTE_ID     [A-Za-z0-9]{16}
DEVICE_ID    [A-Fa-f0-9]{32}
PRIORITY     (LOW|NORMAL|HIGH)

%%

"INIT" {
    initialize_router();
}

"ROUTE"\s+{ROUTE_ID}\s+{DEVICE_ID}\s+{DEVICE_ID}\s+{DEVICE_ID}\s+[0-9]+\s+{PRIORITY} {
    char route_id[16];
    char source[32];
    char dest[32];
    char next_hop[32];
    int hops;
    char priority_str[16];
    int priority = 1;
    
    sscanf(yytext, "ROUTE %s %s %s %s %d %s", route_id, source, dest, next_hop, &hops, priority_str);
    
    if (strcmp(priority_str, "LOW") == 0) priority = 0;
    else if (strcmp(priority_str, "HIGH") == 0) priority = 2;
    
    create_route(route_id, source, dest, next_hop, hops, priority);
}

"SEND"\s+{DEVICE_ID}\s+{DEVICE_ID} {
    char source[32];
    char dest[32];
    
    sscanf(yytext, "SEND %s %s", source, dest);
    route_message(source, dest);
}

"LIST" {
    list_routes();
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    initialize_router();
    yylex();
    return 0;
}
