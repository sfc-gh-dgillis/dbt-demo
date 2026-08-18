#!/usr/bin/env python3
"""
snowclisp - snow cli sort and process (sql files) utility
SQL File Executor for Snowflake CLI
Sorts and executes SQL files with numeric prefixes (e.g., 001-schema.sql)
"""

import re
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


def extract_numeric_prefix(filename: str) -> int:
    """
    Extract numeric prefix from filename (e.g., '001-schema.sql' -> 1)
    
    Args:
        filename: The filename to parse
        
    Returns:
        Integer value of the numeric prefix, or -1 if no match
    """
    match = re.match(r'^(\d+)-', filename)
    if match:
        return int(match.group(1))
    return -1


def get_sorted_sql_files(directory: str, pattern: str = r'^\d+-.*\.sql$') -> Tuple[List[Path], List[Path]]:
    """
    Get all SQL files from directory, separating those matching the numeric prefix pattern
    from those that don't.
    
    Args:
        directory: Path to directory containing SQL files
        pattern: Regex pattern for matching files (default: NNN-*.sql)
        
    Returns:
        Tuple of (matching_files_sorted, non_matching_files)
    """
    dir_path = Path(directory)
    
    if not dir_path.exists():
        raise FileNotFoundError(f"Directory not found: {directory}")
    
    if not dir_path.is_dir():
        raise NotADirectoryError(f"Path is not a directory: {directory}")
    
    # Get all SQL files
    matching_files: List[Tuple[int, Path]] = []
    non_matching_files: List[Path] = []
    pattern_re = re.compile(pattern)
    
    # Iterate over all files in the directory
    for file_path in dir_path.iterdir():
        if file_path.is_file() and file_path.suffix.lower() == '.sql':
            if pattern_re.match(file_path.name):
                # If the file matches the pattern, extract the numeric prefix
                prefix = extract_numeric_prefix(file_path.name)
                matching_files.append((prefix, file_path))
                # If the file does not match the pattern, add it to the non-matching files
            else:
                non_matching_files.append(file_path)
    
    # Sort matching files by numeric prefix
    matching_files.sort(key=lambda x: x[0])
    
    # Return just the paths for matching files, sorted by numeric prefix
    return [path for _, path in matching_files], non_matching_files


def execute_sql_files_with_snowflake_cli(
    connection_name: str,
    sql_files: List[Path],
    verbose: bool = True,
    variables: List[str] = None
) -> bool:
    """
    Execute SQL files using Snowflake CLI in a single command.
    
    Args:
        connection_name: Snowflake CLI connection name
        sql_files: List of SQL file paths to execute (in order)
        verbose: Print execution details
        variables: Optional KEY=value template variables, passed to snow sql as
            -D KEY=value. The SQL files reference them as <% KEY %>. Used by the
            raw seed so one script can target any environment's database.
        
    Returns:
        True if all files executed successfully, False otherwise
    """
    if not sql_files:
        print("No SQL files to execute.")
        return True
    
    variables = variables or []
    
    try:
        # Build command with multiple -f flags
        # Command: snow sql -c <connection_name> -f file1.sql -f file2.sql ...
        cmd = ['snow', 'sql', '-c', connection_name]
        
        for sql_file in sql_files:
            cmd.extend(['-f', str(sql_file)])
        
        for variable in variables:
            cmd.extend(['-D', variable])
        
        if verbose:
            print(f"\n{'='*60}")
            print(f"Executing {len(sql_files)} SQL file(s) in order:")
            for i, sql_file in enumerate(sql_files, 1):
                print(f"  {i}. {sql_file.name}")
            if variables:
                print(f"Template variables:")
                for variable in variables:
                    print(f"  {variable}")
            print(f"{'='*60}")
            print(f"Running command:")
            print(f"  snow sql -c {connection_name} \\")
            for sql_file in sql_files:
                print(f"    -f {sql_file} \\")
            for variable in variables:
                print(f"    -D {variable} \\")
            print()
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        
        if verbose:
            if result.stdout:
                print(result.stdout)
            if result.stderr:
                print(result.stderr, file=sys.stderr)
        
        if verbose:
            print(f"\n{'='*60}")
            print(f"✓ Successfully executed all {len(sql_files)} SQL file(s)")
            print(f"{'='*60}")
        
        return True
            
    except subprocess.CalledProcessError as e:
        error_msg = f"\n{'='*60}\n✗ Failed to execute SQL files\n{'='*60}"
        print(error_msg, file=sys.stderr)
        print(f"Error code: {e.returncode}", file=sys.stderr)
        if e.stdout:
            print(f"\nSTDOUT:\n{e.stdout}", file=sys.stderr)
        if e.stderr:
            print(f"\nSTDERR:\n{e.stderr}", file=sys.stderr)
        
        return False
            
    except FileNotFoundError:
        print("\n" + "="*60, file=sys.stderr)
        print("ERROR: 'snow' command not found.", file=sys.stderr)
        print("Please ensure Snowflake CLI is installed.", file=sys.stderr)
        print("\nInstall with: pip install snowflake-cli-labs", file=sys.stderr)
        print("="*60, file=sys.stderr)
        return False


def main():
    """
    Main entry point for command-line execution.
    
    Usage:
        python script.py <directory> <connection_name> [KEY=value ...]
    """
    if len(sys.argv) < 3:
        print("Usage: python script.py <directory> <connection_name> [KEY=value ...]")
        print("\nExample:")
        print("  python script.py ./tasks/sql my_snowflake_connection")
        print("  python script.py ./tasks/sql my_snowflake_connection base=dev_dbt_demo")
        sys.exit(1)
    
    directory = sys.argv[1]
    connection_name = sys.argv[2]
    
    # Any remaining arguments are snow sql template variables. Validated here
    # rather than passed through blindly: a typo like "base dev_dbt_demo" would
    # otherwise reach snow sql as a malformed -D and fail with a much less
    # obvious message, and an unresolved <% base %> would go on to build objects
    # with a literal template string in their names.
    variables = sys.argv[3:]
    for variable in variables:
        key, separator, value = variable.partition('=')
        if not separator or not key.strip() or not value.strip():
            print(
                f"ERROR: template variable '{variable}' is not in KEY=value form.",
                file=sys.stderr
            )
            sys.exit(1)
    
    try:
        # Get sorted SQL files
        print(f"Scanning directory: {directory}")
        sql_files, non_matching_files = get_sorted_sql_files(directory)
        
        # Warn about non-matching files
        if non_matching_files:
            print(f"\n⚠️  WARNING: Found {len(non_matching_files)} SQL file(s) that don't match naming convention (NNN-*.sql):")
            for file_path in non_matching_files:
                print(f"     - {file_path.name} (not processed)")
        
        if not sql_files:
            print(f"\nNo SQL files with numeric prefix (NNN-*.sql) found in: {directory}")
            sys.exit(0)
        
        print(f"\nFound {len(sql_files)} SQL file(s) with numeric prefix:")
        for i, sql_file in enumerate(sql_files, 1):
            prefix = extract_numeric_prefix(sql_file.name)
            print(f"  {i}. [{prefix:03d}] {sql_file.name}")
        
        # Execute all files in one command
        print(f"\nUsing Snowflake connection: {connection_name}")
        success = execute_sql_files_with_snowflake_cli(
            connection_name,
            sql_files,
            verbose=True,
            variables=variables
        )
        
        sys.exit(0 if success else 1)
        
    except Exception as e:
        print(f"\nERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
