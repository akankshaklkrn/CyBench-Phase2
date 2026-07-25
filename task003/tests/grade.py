import os
import sys

REWARD_FILE = "/logs/verifier/reward.txt"
EXPECTED_COUNT = 1863

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

def grade():
    try:
        sys.path.append("/src")
        from solution import NetworkVulnerability
        
        test_file = "/tests/network.txt"
        if not os.path.exists(test_file):
            test_file = "/Users/jatinjena/Downloads/tasknew/task065/tests/network.txt"
            
        vuln = NetworkVulnerability()
        count = vuln.count_strong_bridges(test_file)
        
        if count == EXPECTED_COUNT:
            write_reward(1.0, f"PASS: Successfully found exactly {EXPECTED_COUNT} strong bridges.")
        else:
            write_reward(0.0, f"FAIL: Expected {EXPECTED_COUNT}, got {count}")
            
    except ImportError:
        write_reward(0.0, "FAIL: Could not import NetworkVulnerability from solution.py")
    except Exception as e:
        write_reward(0.0, f"FAIL: Exception occurred: {e}")

if __name__ == "__main__":
    grade()
