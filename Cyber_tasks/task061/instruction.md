# RSA Timing Side-Channel Attack

## Background

RSA implementations that use the **square-and-multiply** algorithm for modular exponentiation are vulnerable to timing side-channel attacks. The algorithm processes the secret exponent bit-by-bit from the most significant bit (MSB) to the least significant bit (LSB):

- **Bit = 1**: The algorithm performs a **square** operation followed by a **multiply** operation (takes longer).
- **Bit = 0**: The algorithm performs only a **square** operation (takes shorter).

By measuring the time each bit-position step takes, an attacker can statistically distinguish between bit=0 and bit=1, thereby recovering the secret exponent.

## Task

You are given a CSV file (`tests/timing_data.csv`) containing timing measurements from an RSA modular exponentiation operation. The file contains timing samples for each of the 64 bit positions of a secret 64-bit key.

**Data format:**
- Header: `bit_position,sample_index,timing_us`
- `bit_position`: 0 to 63 (0 = MSB, 63 = LSB)
- `sample_index`: 0 to 499 (500 samples per bit position)
- `timing_us`: Timing measurement in microseconds (float)

**Statistical properties of the data:**
- Timing samples have Gaussian noise
- The two distributions (bit=0 vs bit=1) have different means but the same standard deviation

**Your task:** Analyze the timing data to recover the secret 64-bit key.

## Implementation

Create a file `/src/solution.py` containing a class with the following interface:

```python
class TimingAttack:
    def recover_key(self, filepath: str) -> str:
        """
        Analyze timing data to recover the secret RSA exponent.
        
        Args:
            filepath: Path to the CSV file containing timing measurements
            
        Returns:
            The recovered 64-bit key as a lowercase hexadecimal string 
            (16 hex characters, no '0x' prefix). 
            Example: 'a1b2c3d4e5f67890'
        """
        pass
```

Write the result to `/src/results.txt` as the hex string.

## Constraints

- You must use statistical analysis to distinguish bit values from the noisy timing data
- The key must be returned as a **lowercase** hex string of exactly 16 characters (zero-padded if necessary)
- No `0x` prefix in the output
