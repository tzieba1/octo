"""
Test suite for Repo Orchestrator
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Test configuration
TEST_TIMEOUT = 30
TEST_RETRIES = 3