%{
/* Basic Ecosync Setup Example */
/* Demonstrates core Ecosync functionality and workflow */
%}

%option noyywrap
%option yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void print_example() {
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║       Ecosync - Multi-Device Web Connection Example          ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n\n");
    
    printf("STEP 1: Initialize System\n");
    printf("  Command: INIT\n");
    printf("  Purpose: Initialize all managers and registries\n\n");
    
    printf("STEP 2: Register Devices\n");
    printf("  Commands:\n");
    printf("    REGISTER 11111111111111111111111111111111 sensor_01 192.168.1.10 8080 SENSOR\n");
    printf("    REGISTER 22222222222222222222222222222222 actuator_01 192.168.1.20 8081 ACTUATOR\n");
    printf("    REGISTER 33333333333333333333333333333333 hub_01 192.168.1.30 8082 HUB\n");
    printf("  Purpose: Register three IoT devices in the network\n\n");
    
    printf("STEP 3: Query Device Information\n");
    printf("  Command: QUERY 11111111111111111111111111111111\n");
    printf("  Purpose: Retrieve device details\n\n");
    
    printf("STEP 4: Create Connections\n");
    printf("  Command: CREATE conn_001 11111111111111111111111111111111 22222222222222222222222222222222\n");
    printf("  Purpose: Establish connection between sensor and actuator\n\n");
    
    printf("STEP 5: Open Connection\n");
    printf("  Command: OPEN conn_001\n");
    printf("  Purpose: Activate the connection\n\n");
    
    printf("STEP 6: Send 1-bit Messages\n");
    printf("  Command: SEND msg_001 1 11111111111111111111111111111111 22222222222222222222222222222222 DATA\n");
    printf("  Purpose: Transmit a 1-bit message (DATA type)\n\n");
    
    printf("STEP 7: Start Network Discovery\n");
    printf("  Command: DISCOVER disc_001 11111111111111111111111111111111 255\n");
    printf("  Purpose: Discover other devices on network\n\n");
    
    printf("STEP 8: List System State\n");
    printf("  Commands:\n");
    printf("    LIST (Device List)\n");
    printf("    COUNT (Device Count)\n");
    printf("  Purpose: View current system state\n\n");
    
    printf("STEP 9: Close Connection\n");
    printf("  Command: CLOSE conn_001\n");
    printf("  Purpose: Terminate the connection\n\n");
    
    printf("═══════════════════════════════════════════════════════════════\n\n");
}

void print_workflow_diagram() {
    printf("Ecosync Data Flow:\n\n");
    printf("  [Device Registry] ──────> [Connection Manager]\n");
    printf("         │                           │
");
    printf("         └──────> [Message Router] <─┘
");
    printf("                        │
");
    printf("              [Protocol Handler]
");
    printf("                        │
");
    printf("        [Network Adapter] ──> [Discovery Engine]
");
    printf("\n");
}
%}

%%

"EXAMPLE" {
    print_example();
}

"WORKFLOW" {
    print_workflow_diagram();
}

"HELP" {
    printf("\n=== Ecosync Help ===\n");
    printf("Commands:\n");
    printf("  EXAMPLE  - Show setup example\n");
    printf("  WORKFLOW - Show data flow diagram\n");
    printf("  HELP     - Show this help\n\n");
}

[ \t\n]+ { /* ignore whitespace */ }

. { /* ignore unknown characters */ }

%%

int main() {
    printf("\n╔════════════════════════════════════════════════════════╗\n");
    printf("║  Ecosync - Seamless Multi-Device Web Connection       ║\n");
    printf("║  Language-of-Things 1-bit IoT Protocol                ║\n");
    printf("╚════════════════════════════════════════════════════════╝\n\n");
    printf("Type 'EXAMPLE' for setup example, 'WORKFLOW' for diagram, or 'HELP'\n\n");
    yylex();
    return 0;
}
