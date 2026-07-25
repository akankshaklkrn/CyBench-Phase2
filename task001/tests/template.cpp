#include <atomic>

template <typename T>
class LockFreeStack {
private:
    struct Node {
        T data;
        Node* next;
        Node(T const& data_) : data(data_) {}
    };
    std::atomic<Node*> head;

public:
    LockFreeStack() : head(nullptr) {}

    void push(T const& data) {
        Node* const new_node = new Node(data);
        new_node->next = head.load();
        while (!head.compare_exchange_weak(new_node->next, new_node));
    }

    bool pop(T& result) {
        Node* old_head = head.load();
        while (old_head && !head.compare_exchange_weak(old_head, old_head->next));
        
        if (old_head) {
            result = old_head->data;
            // VULNERABILITY: Immediately deleting the node causes the ABA problem 
            // if another thread reallocates this address before a paused thread 
            // finishes its compare_exchange_weak.
            delete old_head; 
            return true;
        }
        return false;
    }
};
