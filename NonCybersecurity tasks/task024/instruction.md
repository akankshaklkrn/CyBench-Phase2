# Task: ACID Write-Ahead Log (WAL) Crash Recovery Engine (ARIES Protocol)

Your goal is to implement an ACID Write-Ahead Log (WAL) Crash Recovery Engine in C using the classic ARIES protocol.

In `target.c`, you are given a simulated database storage engine with 256 disk pages (4KB each) and a persistent log file containing transaction records (`LOG_UPDATE`, `LOG_COMMIT`, `LOG_ABORT`, `LOG_CHECKPOINT`).
A simulated power failure occurs in the middle of executing 50 concurrent transactions, leaving the disk pages in a dirty, uncommitted, and partially modified state.

You must implement the function `recover_from_wal(log_record_t *log_entries, int num_entries, page_t *disk_pages)` which performs the three mandatory ARIES recovery phases:
1. **Analysis Phase**: Scan forward from the start of the log (or last checkpoint) to identify all active (uncommitted) transactions and populate the Dirty Page Table (DPT) with the smallest LSN (`recLSN`) that dirtied each page.
2. **Redo Phase**: Scan forward starting from the minimum `recLSN` across all dirty pages. Re-apply logged update operations to restore the disk pages to their exact state at the moment of the crash (Repeating History).
3. **Undo Phase**: Scan backward from the end of the log to reverse all update operations belonging to transactions that were active (uncommitted) at the time of the crash. For each undone operation, you must record a Compensation Log Record (CLR) to guarantee idempotency.

## Requirements
- **No Uncommitted Leaks**: Every transaction without a `LOG_COMMIT` or `LOG_ABORT` prior to the crash must be completely rolled back during the Undo phase.
- **No Committed Loss**: Every transaction with a `LOG_COMMIT` record must have all its page modifications preserved after Redo.
- **Memory & Sanitizer Safety**: Compiled with AddressSanitizer (`-fsanitize=address`). You must not cause out-of-bounds page indexing or memory corruption during log parsing.

When you are done, compile the code using `gcc -O2 -Wall -Werror -fsanitize=address -o /out/wal_bench target.c` and ensure it runs successfully. If it prints "FLAG: WAL Crash Recovery Success!", you have passed.
