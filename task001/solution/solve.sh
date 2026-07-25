#!/bin/bash
cat << 'EOF' > solution.cpp
#include <memory>
#include <atomic>

template <typename T>
class LockFreeStack {
private:
    struct Node {
        T data;
        std::shared_ptr<Node> next;
        Node(T const& data_) : data(data_) {}
    };

    std::shared_ptr<Node> head;

public:
    LockFreeStack() : head(nullptr) {}

    void push(T const& data) {
        std::shared_ptr<Node> new_node = std::make_shared<Node>(data);
        new_node->next = std::atomic_load(&head);
        while (!std::atomic_compare_exchange_weak(&head, &new_node->next, new_node));
    }

    bool pop(T& result) {
        std::shared_ptr<Node> old_head = std::atomic_load(&head);
        while (old_head && !std::atomic_compare_exchange_weak(&head, &old_head, old_head->next));
        if (old_head) {
            result = old_head->data;
            return true;
        }
        return false;
    }
};
EOF
