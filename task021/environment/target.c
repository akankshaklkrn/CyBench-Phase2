#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>

#define BUFFER_SIZE 1024
#define NUM_PRODUCERS 8
#define NUM_CONSUMERS 8
#define ITEMS_PER_PRODUCER 25000

typedef struct ring_buffer_t {
    int buffer[BUFFER_SIZE];
    _Atomic size_t head;
    _Atomic size_t tail;
} ring_buffer_t;

ring_buffer_t rb;
_Atomic int total_produced = 0;
_Atomic int total_consumed = 0;

// TODO: Implement lock-free ring_push and ring_pop with proper memory ordering barriers
void ring_push(ring_buffer_t *rb, int value) {
    // Implement lock-free push with memory_order_release / acquire
}

void ring_pop(ring_buffer_t *rb, int *value) {
    // Implement lock-free pop with memory_order_acquire / release
}

void* producer_func(void* arg) {
    int id = *(int*)arg;
    for (int i = 0; i < ITEMS_PER_PRODUCER; i++) {
        ring_push(&rb, (id * ITEMS_PER_PRODUCER) + i);
        atomic_fetch_add(&total_produced, 1);
    }
    return NULL;
}

void* consumer_func(void* arg) {
    int val;
    for (int i = 0; i < ITEMS_PER_PRODUCER; i++) {
        ring_pop(&rb, &val);
        atomic_fetch_add(&total_consumed, 1);
    }
    return NULL;
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting TSAN + UBSAN Bounded Ring Buffer Stress Test...\n");
    atomic_init(&rb.head, 0);
    atomic_init(&rb.tail, 0);
    
    pthread_t producers[NUM_PRODUCERS];
    pthread_t consumers[NUM_CONSUMERS];
    int prod_ids[NUM_PRODUCERS];
    int cons_ids[NUM_CONSUMERS];
    
    for (int i = 0; i < NUM_PRODUCERS; i++) {
        prod_ids[i] = i;
        pthread_create(&producers[i], NULL, producer_func, &prod_ids[i]);
    }
    for (int i = 0; i < NUM_CONSUMERS; i++) {
        cons_ids[i] = i;
        pthread_create(&consumers[i], NULL, consumer_func, &cons_ids[i]);
    }
    
    for (int i = 0; i < NUM_PRODUCERS; i++) {
        pthread_join(producers[i], NULL);
    }
    for (int i = 0; i < NUM_CONSUMERS; i++) {
        pthread_join(consumers[i], NULL);
    }
    
    int expected = NUM_PRODUCERS * ITEMS_PER_PRODUCER;
    if (total_produced != expected || total_consumed != expected) {
        printf("Invariant violated: Item counts mismatch! Produced: %d, Consumed: %d\n",
               total_produced, total_consumed);
        return 1;
    }

    printf("FLAG: Ring Buffer TSAN Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "Ring-TSAN Triggered\n");
        fclose(f);
    }
    return 0;
}
