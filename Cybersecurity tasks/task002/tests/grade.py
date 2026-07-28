import os
import sys
import hashlib

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))
    with open("/src/debug.log", "w") as f:
        f.write(f"Reward: {reward}\nReason: {reason}\n")

def grade():
    try:
        sys.path.append("/src")
        from solution import OramClient

        D = 3
        Z = 4
        leaf_seq = [9, 12, 10, 15, 8, 14, 11, 13, 9, 12, 8, 15, 11, 10, 14, 13]
        rng_idx = 0
        def get_leaf():
            nonlocal rng_idx
            val = leaf_seq[rng_idx % len(leaf_seq)]
            rng_idx += 1
            return val

        client = OramClient(D, Z, get_leaf)
        client.access('write', 5, 100)
        client.access('write', 2, 200)
        
        val = client.access('read', 5)
        if val != 100:
            write_reward(0.0, f"FAIL: Expected read of block 5 to return 100, got {val}")
            return
            
        client.access('write', 7, 700)
        client.access('write', 0, 50)
        client.access('write', 3, 300)

        tree = client.get_server_tree()
        
        EXPECTED_TREE = {1: {'blocks': [(3, 300), (-1, 0), (-1, 0), (-1, 0)],
     'hash': '4c2e927fb125efc2aa3410d18a4db5ad8cfe9149d6c6aaa14e903a65f730049c',
     'version': 6},
 2: {'blocks': [(0, 50), (-1, 0), (-1, 0), (-1, 0)],
     'hash': '821b248e05b2791335ca95e1c66f6b936397c3cc61dee282adf7b599b6e58140',
     'version': 3},
 3: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
     'hash': 'e01d4b22591bae3055cf1e8f0581c82e303fad0d08d5087d2b1438c7a3306d58',
     'version': 3},
 4: {'blocks': [(5, 100), (-1, 0), (-1, 0), (-1, 0)],
     'hash': '52000254659ca63b54c6519a28a93c77b60c5b79298032fa75d56100b406ff8d',
     'version': 2},
 5: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
     'hash': '33f6a72e2eb9fd749485a140851142b35a72c0fd301a11178b861c3816be3aac',
     'version': 1},
 6: {'blocks': [(2, 200), (-1, 0), (-1, 0), (-1, 0)],
     'hash': 'c5ca07ccb3859628d4f5ba4d9294f8ec3e4803cd27801c21b81379e90fffe0b1',
     'version': 1},
 7: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
     'hash': 'eafd1a620964ec241b0aab950759d6a598d07b19561559bd827d652f2cba96b9',
     'version': 2},
 8: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
     'hash': '0d8cb2dd3417a44ef5abd89c9f17299a4f2651c6ba470af36ff47c05a0731255',
     'version': 0},
 9: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
     'hash': '4141e8be6e4d034bb6faaf2b0ed770ecb35652a12384d21ec7aa6e2aab1c21f2',
     'version': 2},
 10: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
      'hash': 'ee5745fa22f2630dd436dfacda6bca105001db583203c2fac0e7efc75e457eb5',
      'version': 1},
 11: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
      'hash': '07ac3198fad6e545a994c0f5a640ff0aef9f8084af8db9e7b94bdef3cf6b7132',
      'version': 0},
 12: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
      'hash': '40647ee6ba1b144d06e7a9bad921eb9fd2d5a018c954024f5c9f5ecd6c2adf79',
      'version': 0},
 13: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
      'hash': '1950d7b61d1bbb5fdc8d56475070a6ac998879aa4334473f5f5c221fa97c46d6',
      'version': 1},
 14: {'blocks': [(-1, 0), (-1, 0), (-1, 0), (-1, 0)],
      'hash': '4c0e319ca8c933a051ceec5312acf9c0655dca6528ecaf7ed0b90a2c535552e8',
      'version': 1},
 15: {'blocks': [(7, 700), (-1, 0), (-1, 0), (-1, 0)],
      'hash': 'cef9d185cdc51eb73ab23377f9592fd60c46732ae1492a273f6459def8912e59',
      'version': 1}}

        for node_id, node_data in EXPECTED_TREE.items():
            got_node = tree.get(node_id)
            if not got_node:
                write_reward(0.0, f"FAIL: Missing node {node_id} from server tree.")
                return
            if got_node["version"] != node_data["version"]:
                write_reward(0.0, f"FAIL: Node {node_id} version mismatch. Expected {node_data['version']}, got {got_node['version']}")
                return
            if got_node["hash"] != node_data["hash"]:
                write_reward(0.0, f"FAIL: Node {node_id} SHA256 tag mismatch. Expected {node_data['hash']}, got {got_node['hash']}")
                return

        # Test Integrity Violation Trigger
        tree[1]["hash"] = "tampered_hash_tag"
        try:
            client.access('read', 3)
            write_reward(0.0, "FAIL: Client failed to raise Exception when node SHA-256 integrity tag was tampered.")
            return
        except Exception:
            pass # Expected behavior

        write_reward(1.0, "PASS: Authenticated Path ORAM client executed and verified perfectly.")

    except ImportError:
        write_reward(0.0, "FAIL: Could not import OramClient from solution.py")
        return
    except Exception as e:
        write_reward(0.0, f"FAIL: Exception occurred: {e}")
        return

if __name__ == "__main__":
    grade()
