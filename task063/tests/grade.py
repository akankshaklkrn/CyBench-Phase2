#!/usr/bin/env python3
"""
Grader for Task 070: X.509 Certificate Chain Validator.
Checks solution results against expected validation outcomes.
"""

import json
import subprocess
import sys
import os


def write_reward(reward):
    reward_dir = '/logs/verifier'
    # Fallback for local testing
    if not os.path.isdir('/logs'):
        reward_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'verifier')
    os.makedirs(reward_dir, exist_ok=True)
    path = os.path.join(reward_dir, 'reward.txt')
    with open(path, 'w') as f:
        f.write(str(reward))
    print(f"Reward: {reward}")


def grade():
    results_path = '/src/results.txt'
    solution_path = '/src/solution.py'
    expected_path = '/tests/expected_results.json'

    # Fallback paths for local testing
    if not os.path.exists(expected_path):
        expected_path = os.path.join(os.path.dirname(__file__), 'expected_results.json')

    # If results don't exist, try running the solution
    if not os.path.exists(results_path):
        if not os.path.exists(solution_path):
            print("ERROR: No solution.py found at /src/solution.py")
            write_reward(0.0)
            return
        print("Running solution.py...")
        try:
            result = subprocess.run(
                ['python3', solution_path],
                timeout=120,
                capture_output=True,
                text=True,
                cwd='/src'
            )
            print(f"STDOUT: {result.stdout}")
            if result.stderr:
                print(f"STDERR: {result.stderr}")
            if result.returncode != 0:
                print(f"Solution exited with code {result.returncode}")
                write_reward(0.0)
                return
        except subprocess.TimeoutExpired:
            print("ERROR: Solution timed out after 120 seconds")
            write_reward(0.0)
            return
        except Exception as e:
            print(f"ERROR: Failed to run solution: {e}")
            write_reward(0.0)
            return

    if not os.path.exists(results_path):
        print("ERROR: Solution did not produce /src/results.txt")
        write_reward(0.0)
        return

    # Check for forbidden imports
    if os.path.exists(solution_path):
        with open(solution_path, 'r') as f:
            code = f.read()
        forbidden = ['cryptography', 'pyOpenSSL', 'asn1crypto', 'OpenSSL', 'pyasn1']
        for lib in forbidden:
            if f'import {lib}' in code or f'from {lib}' in code:
                print(f"FORBIDDEN IMPORT: {lib} detected in solution.py")
                write_reward(0.0)
                return

    # Load results
    try:
        with open(results_path, 'r') as f:
            results = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"ERROR: Could not parse results.txt: {e}")
        write_reward(0.0)
        return

    # Load expected
    try:
        with open(expected_path, 'r') as f:
            expected = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"ERROR: Could not parse expected_results.json: {e}")
        write_reward(0.0)
        return

    # Compare results
    total = 0
    passed = 0

    for chain_file, exp in expected.items():
        if chain_file == 'timestamp':
            continue
        total += 1

        if chain_file not in results:
            print(f"FAIL [{chain_file}]: Missing from results")
            continue

        res = results[chain_file]

        # Check 'valid' field
        res_valid = res.get('valid')
        exp_valid = exp['valid']
        if res_valid != exp_valid:
            print(f"FAIL [{chain_file}]: valid={res_valid}, expected={exp_valid}")
            continue

        # Check 'chain_length' field
        res_cl = res.get('chain_length')
        exp_cl = exp['chain_length']
        if res_cl != exp_cl:
            print(f"FAIL [{chain_file}]: chain_length={res_cl}, expected={exp_cl}")
            continue

        # Check 'errors' field
        res_errors = sorted(res.get('errors', []))
        exp_errors = sorted(exp.get('errors', []))
        if res_errors != exp_errors:
            print(f"FAIL [{chain_file}]: errors={res_errors}, expected={exp_errors}")
            continue

        passed += 1
        print(f"PASS [{chain_file}]")

    if total > 0 and passed == total:
        reward = 1.0
    else:
        reward = 0.0

    print(f"\nResult: {passed}/{total} chains validated correctly")
    write_reward(reward)


if __name__ == '__main__':
    grade()
