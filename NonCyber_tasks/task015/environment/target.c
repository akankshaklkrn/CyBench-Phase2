#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { JSON_NULL, JSON_BOOL, JSON_NUM, JSON_STR, JSON_ARR, JSON_OBJ } json_type;

typedef struct json_node json_node;

typedef struct json_kv {
    char *key;
    json_node *value;
    struct json_kv *next;
} json_kv;

typedef struct json_arr_elem {
    json_node *value;
    struct json_arr_elem *next;
} json_arr_elem;

struct json_node {
    json_type type;
    union {
        int boolean;
        double number;
        char *string;
        json_arr_elem *array;
        json_kv *object;
    } val;
};

// TODO: Implement parse_json and free_json
json_node* parse_json(const char *json) {
    // Implement parsing logic here
    return NULL;
}

void free_json(json_node *node) {
    // Implement recursive freeing logic here
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting JSON ASAN Stress Test...\n");
    
    // Massive nested JSON string
    const char *payload = "{\"status\": \"ok\", \"data\": [1, 2, {\"id\": 999, \"name\": \"test_user\", \"tags\": [\"admin\", \"user\", \"power\"]}, false, null], \"metadata\": {\"count\": 5, \"version\": \"1.0.0\"}}";
    
    json_node *root = parse_json(payload);
    
    if (root == NULL || root->type != JSON_OBJ) {
        printf("Invariant violated: Failed to parse root object!\n");
        if (root) free_json(root);
        return 1;
    }
    
    // Test finishes, now trigger the recursive free.
    // If ASAN detects any memory leaks upon exit, the test fails.
    free_json(root);

    printf("FLAG: JSON ASAN Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "JSON-ASAN Triggered\n");
        fclose(f);
    }
    return 0;
}
