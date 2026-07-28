#include <atomic>

template <typename T>
class LockFreeStack {
private:
    struct Node {
        T data;
        Node* next;
        Node(T const& data_) : data(data_) {}
    };

    struct alignas(16) TaggedNode {
        Node* ptr;
        uint64_t tag;
    };

    std::atomic<TaggedNode> head;

public:
    LockFreeStack() {
        head.store({nullptr, 0});
    }

    void push(T const& data) {
        Node* const new_node = new Node(data);
        TaggedNode old_head = head.load(std::memory_order_relaxed);
        TaggedNode new_head;
        do {
            new_node->next = old_head.ptr;
            new_head.ptr = new_node;
            new_head.tag = old_head.tag + 1;
        } while (!head.compare_exchange_weak(old_head, new_head, 
                                             std::memory_order_release, 
                                             std::memory_order_relaxed));
    }

    bool pop(T& result) {
        TaggedNode old_head = head.load(std::memory_order_acquire);
        TaggedNode new_head;
        while (true) {
            if (!old_head.ptr) {
                return false;
            }
            new_head.ptr = old_head.ptr->next;
            new_head.tag = old_head.tag + 1;
            if (head.compare_exchange_weak(old_head, new_head, 
                                           std::memory_order_release, 
                                           std::memory_order_acquire)) {
                result = old_head.ptr->data;
                delete old_head.ptr;
                return true;
            }
        }
    }
};
