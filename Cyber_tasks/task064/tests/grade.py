import os
import sys

REWARD_FILE = "/logs/verifier/reward.txt"
EXPECTED_STRING = "Algorithms and Stream Ciphers are beautiful! " * 15 + "End of secure transmission."

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

def grade():
    try:
        sys.path.append("/src")
        from solution import LZBitDecompressor
        
        test_file = "/tests/compressed.bin"
        if not os.path.exists(test_file):
            test_file = "/Users/jatinjena/Downloads/tasknew/task064/tests/compressed.bin"
            
        with open(test_file, "rb") as f:
            data = f.read()
            
        decompressor = LZBitDecompressor()
        decoded = decompressor.decompress(data)
        
        if decoded == EXPECTED_STRING:
            write_reward(1.0, "PASS: Successfully descrambled and decompressed payload.")
        else:
            write_reward(0.0, f"FAIL: Decoded string mismatch. Expected length {len(EXPECTED_STRING)}, got {len(decoded)}.")
            
    except Exception as e:
        write_reward(0.0, f"FAIL: Exception occurred during decompression/descrambling: {e}")

if __name__ == "__main__":
    grade()
