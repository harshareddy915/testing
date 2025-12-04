import os
import shutil
from pathlib import Path

def move_paths_with_structure(input_paths, destination):
    """
    Move source paths to destination while preserving their folder structure.
    
    Args:
        input_paths (str): Comma-separated source paths
        destination (str): Destination folder path
    """
    # Parse comma-separated input
    source_paths = [path.strip() for path in input_paths.split(',')]
    
    # Create destination folder if it doesn't exist
    dest_path = Path(destination)
    dest_path.mkdir(parents=True, exist_ok=True)
    
    moved_items = []
    errors = []
    
    for source in source_paths:
        source_path = Path(source)
        
        # Check if source path exists
        if not source_path.exists():
            error_msg = f"Source path does not exist: {source}"
            print(f"❌ {error_msg}")
            errors.append(error_msg)
            continue
        
        # Get the folder name to preserve (e.g., "test1/testa" -> "test1/testa")
        # Preserve the entire relative path structure
        folder_name = source_path.as_posix()
        
        # Create destination path with preserved structure
        dest_item = dest_path / folder_name
        
        print(f"\n📁 Processing: {source}")
        print(f"   Moving to: {dest_item}")
        
        try:
            # Check if destination already exists
            if dest_item.exists():
                print(f"⚠️  Destination already exists: {dest_item} - Skipping")
                continue
            
            # Create parent directories if needed
            dest_item.parent.mkdir(parents=True, exist_ok=True)
            
            # Move the entire source path (file or folder) to destination
            shutil.move(str(source_path), str(dest_item))
            
            item_type = "📂 Folder" if dest_item.is_dir() else "📄 File"
            moved_items.append(folder_name)
            print(f"✅ Moved {item_type}: {folder_name}")
            
        except Exception as e:
            error_msg = f"Failed to move {source}: {str(e)}"
            print(f"❌ {error_msg}")
            errors.append(error_msg)
    
    # Summary
    print(f"\n{'='*60}")
    print(f"📊 Summary:")
    print(f"   Total items moved: {len(moved_items)}")
    print(f"   Errors: {len(errors)}")
    print(f"{'='*60}")
    
    return moved_items, errors


if __name__ == "__main__":
    # Example usage with interactive input
    print("Move Paths with Structure Preservation")
    print("="*60)
    input_paths = input("Enter comma-separated source paths: ")
    destination = input("Enter destination folder path: ")
    
    print(f"\n🚀 Starting move operation...")
    moved, errors = move_paths_with_structure(input_paths, destination)
    
    if errors:
        print(f"\n⚠️  Operation completed with {len(errors)} error(s)")
    else:
        print(f"\n✨ Operation completed successfully!")
