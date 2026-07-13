#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_NOTES 10

char* notes[MAX_NOTES];
int is_admin = 0;

void flush_input() {
    int c;
    while ((c = getchar()) != '\n' && c != EOF) {}
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stdin, NULL, _IONBF, 0);
    int choice = 0;
    int idx = 0;
    
    printf("Welcome to the Secure Note Taker!\n");
    
    while (1) {
        printf("\n--- Main Menu ---\n");
        printf("1. Add Note\n");
        printf("2. Delete Note\n");
        printf("3. Edit Note\n");
        printf("4. View Admin Dashboard\n");
        printf("5. Exit\n");
        printf("> ");
        
        if (scanf("%d", &choice) != 1) {
            flush_input();
            continue;
        }
        flush_input();
        
        if (choice == 1) {
            printf("Index (0-%d): ", MAX_NOTES - 1);
            if (scanf("%d", &idx) == 1 && idx >= 0 && idx < MAX_NOTES) {
                flush_input();
                if (notes[idx] == NULL) {
                    // Always allocate size 0x20 to ensure it goes into a specific tcache bin
                    notes[idx] = (char*)malloc(0x20);
                    printf("Note added.\n");
                } else {
                    printf("Note already exists at that index.\n");
                }
            } else {
                flush_input();
                printf("Invalid index.\n");
            }
        } 
        else if (choice == 2) {
            printf("Index (0-%d): ", MAX_NOTES - 1);
            if (scanf("%d", &idx) == 1 && idx >= 0 && idx < MAX_NOTES) {
                flush_input();
                if (notes[idx] != NULL) {
                    free(notes[idx]);
                    // VULNERABILITY: Pointer is not set to NULL
                    // notes[idx] = NULL;
                    printf("Note deleted.\n");
                } else {
                    printf("Note is already empty.\n");
                }
            } else {
                flush_input();
                printf("Invalid index.\n");
            }
        }
        else if (choice == 3) {
            printf("Index (0-%d): ", MAX_NOTES - 1);
            if (scanf("%d", &idx) == 1 && idx >= 0 && idx < MAX_NOTES) {
                flush_input();
                if (notes[idx] != NULL) {
                    // VULNERABILITY: Use-After-Free Write. We can write to a freed chunk!
                    printf("Enter note content: ");
                    // Limit read to 8 bytes. This is enough to overwrite the tcache fd pointer!
                    read(0, notes[idx], 8);
                    printf("Note edited.\n");
                } else {
                    printf("No note at that index to edit.\n");
                }
            } else {
                flush_input();
                printf("Invalid index.\n");
            }
        }
        else if (choice == 4) {
            if (is_admin == 0) {
                printf("Access denied. You are not an admin.\n");
            } else {
                printf("Welcome, Admin!\n");
                printf("FLAG: Tcache Poisoning Success!\n");
                FILE *f = fopen("/tmp/success.txt", "w");
                if(f) {
                    fprintf(f, "Tcache Poisoning Triggered\n");
                    fclose(f);
                }
            }
        }
        else if (choice == 5) {
            printf("Goodbye!\n");
            break;
        }
        else {
            printf("Invalid choice.\n");
        }
    }
    return 0;
}
