#!/usr/bin/env python3
"""
Script to move multiple directories to a destination while preserving their structure.
Usage: python move_multiple_dirs.py "source1,source2,source3" destination_dir
"""

import os
import shutil
import sys
from pathlib import Path


def move_directories(sources_str, destination):
    """
    Move multiple source directories to a destination directory.
    
    Args:
        sources_str: Comma-separated string of source paths
        destination: Destination directory path
    """
    # Parse comma-separated sources
    sources = [s.strip() for s in sources_str.split(',')]
    
    # Create destination if it doesn't exist
    dest_path = Path(destination)
    dest_path.mkdir(parents=True, exist_ok=True)
    
    print(f"Destination directory: {dest_path.absolute()}")
    print(f"Moving {len(sources)} source(s)...\n")
    
    for source in sources:
        source_path = Path(source)
        
        # Check if source exists
        if not source_path.exists():
            print(f"❌ Error: Source '{source}' does not exist. Skipping.")
            continue
        
        # Determine the destination path
        # This preserves the full source path structure
        dest_full_path = dest_path / source_path
        
        try:
            # Create parent directories if they don't exist
            dest_full_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Move the source to destination
            print(f"Moving: {source_path} -> {dest_full_path}")
            shutil.move(str(source_path), str(dest_full_path))
            print(f"✓ Successfully moved {source}\n")
            
        except Exception as e:
            print(f"❌ Error moving {source}: {str(e)}\n")


def list_moved_files(destination):
    """List all files in the destination directory tree."""
    dest_path = Path(destination)
    
    if not dest_path.exists():
        print("Destination directory doesn't exist.")
        return
    
    print("\n" + "="*60)
    print("Files in destination directory:")
    print("="*60)
    
    for root, dirs, files in os.walk(dest_path):
        for file in files:
            file_path = Path(root) / file
            print(file_path)


def main():
    if len(sys.argv) != 3:
        print("Usage: python move_multiple_dirs.py 'source1,source2,source3' destination_dir")
        print("\nExample:")
        print("  python move_multiple_dirs.py 'test1/testa,test2/testb' destination/")
        sys.exit(1)
    
    sources_str = sys.argv[1]
    destination = sys.argv[2]
    
    print("="*60)
    print("Multi-Directory Move Script")
    print("="*60)
    
    # Confirm before moving
    print(f"\nSources: {sources_str}")
    print(f"Destination: {destination}")
    
    response = input("\nProceed with moving? (y/n): ")
    if response.lower() != 'y':
        print("Operation cancelled.")
        sys.exit(0)
    
    print()
    move_directories(sources_str, destination)
    list_moved_files(destination)


if __name__ == "__main__":
    main()
