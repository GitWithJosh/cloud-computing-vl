#!/usr/bin/env python3
"""
Debug script to test file reading before deployment
Usage: python3 debug_files.py [v1|v2]
"""

import sys
import os

def read_file(filename):
    try:
        with open(filename, 'r') as f:
            content = f.read()
            return content
    except FileNotFoundError:
        print(f"❌ ERROR: File {filename} not found")
        return ""
    except Exception as e:
        print(f"❌ ERROR reading {filename}: {e}")
        return ""

def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "v1"
    script_name = f"calo_guessr_{version}.py"
    
    print(f"🔍 Debugging file reading for version {version}")
    print(f"📂 Current directory: {os.getcwd()}")
    print(f"📋 Files in current directory:")
    
    for file in os.listdir('.'):
        if os.path.isfile(file):
            size = os.path.getsize(file)
            print(f"   📄 {file} ({size} bytes)")
    
    print(f"\n🔍 Testing file reads:")
    
    # Test script file
    print(f"\n📄 Reading {script_name}:")
    script_content = read_file(script_name)
    if script_content:
        lines = len(script_content.split('\n'))
        chars = len(script_content)
        print(f"   ✅ SUCCESS: {lines} lines, {chars} characters")
        print(f"   📋 First few lines:")
        for i, line in enumerate(script_content.split('\n')[:3]):
            print(f"      {i+1}: {line[:80]}{'...' if len(line) > 80 else ''}")
    else:
        print(f"   ❌ FAILED to read {script_name}")
    
    # Test requirements file
    print(f"\n📦 Reading requirements.txt:")
    req_content = read_file("requirements.txt")
    if req_content:
        lines = len(req_content.split('\n'))
        chars = len(req_content)
        print(f"   ✅ SUCCESS: {lines} lines, {chars} characters")
        print(f"   📋 Contents:")
        for line in req_content.strip().split('\n'):
            if line.strip():
                print(f"      📦 {line.strip()}")
    else:
        print(f"   ⚠️  requirements.txt not found or empty")
    
    # Test what would be embedded
    print(f"\n🔧 Testing embedded content:")
    if script_content:
        # Simulate what will be in the cloud-init script
        embedded_check = f"""cat > {script_name} << 'PYTHON_SCRIPT_EOF'
{script_content}
PYTHON_SCRIPT_EOF"""
        print(f"   ✅ Script embedding would work ({len(embedded_check)} chars total)")
    else:
        print(f"   ❌ Script embedding would FAIL - no content")
    
    if req_content:
        embedded_req = f"""cat > requirements.txt << 'REQUIREMENTS_EOF'
{req_content}
REQUIREMENTS_EOF"""
        print(f"   ✅ Requirements embedding would work ({len(embedded_req)} chars total)")
    else:
        print(f"   ⚠️  Requirements embedding would be skipped")
    
    print(f"\n🎯 Summary:")
    if script_content:
        print(f"   ✅ {script_name} is ready for deployment")
    else:
        print(f"   ❌ {script_name} is NOT ready - file missing or empty")
        return 1
    
    if req_content:
        print(f"   ✅ requirements.txt is ready for deployment")
    else:
        print(f"   ⚠️  requirements.txt missing - deployment will continue without dependencies")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())