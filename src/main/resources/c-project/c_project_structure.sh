#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Project setup function
create_c_learning_project() {
    # Default values
    DEFAULT_PROJECT_NAME="c-learning-experiments"
    PROJECT_NAME=${1:-$DEFAULT_PROJECT_NAME}

    # Determine project path
    if [ $# -eq 2 ]; then
        PROJECT_PATH="$2"
    else
        PROJECT_PATH="$HOME/Projects"
    fi

    # Ensure the project path exists
    mkdir -p "$PROJECT_PATH"

    # Full project directory
    FULL_PROJECT_DIR="$PROJECT_PATH/$PROJECT_NAME"

    # Check if project directory already exists
    if [ -d "$FULL_PROJECT_DIR" ]; then
        echo -e "${RED}Error: Project directory already exists at $FULL_PROJECT_DIR${NC}"
        exit 1
    fi

    # Create project root directory
    mkdir -p "$FULL_PROJECT_DIR"
    cd "$FULL_PROJECT_DIR" || exit 1

    # Create directory structure
    mkdir -p src/os_concepts/{process_management,memory_management,ipc,threading,signals} \
             src/utilities \
             include/os_concepts \
             lib \
             tests \
             build \
             docs

    # Create .gitkeep in build to ensure directory is tracked
    touch build/.gitkeep

    # Create Makefile
    cat > Makefile << 'EOF'
CC = gcc
CFLAGS = -Wall -Wextra -I./include
LDFLAGS = -pthread

# Source directories
SRC_DIR = src
BUILD_DIR = build

# Find all source files
SOURCES = $(shell find $(SRC_DIR) -name "*.c")
OBJECTS = $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)

# Main target
TARGET = os_experiments

# Default target
all: $(BUILD_DIR)/$(TARGET)

# Link object files
$(BUILD_DIR)/$(TARGET): $(OBJECTS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)

# Compile source files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Run the program
run: $(BUILD_DIR)/$(TARGET)
	./$(BUILD_DIR)/$(TARGET)

.PHONY: all clean run
EOF

    # Create README.md
    cat > README.md << EOF
# $PROJECT_NAME

## Project Overview
This project is a structured environment for learning and experimenting with operating system concepts in C.

## Project Location
- Path: $FULL_PROJECT_DIR

## Setup and Compilation
1. Ensure you have GCC and make installed
2. Run \`make\` to build the project
3. Run \`make run\` to execute

## Getting Started
- Explore the \`src/\` directory for experiment sources
- Add your learning notes in \`docs/notes.md\`
- Create new experiments in the appropriate subdirectories
EOF

    # Create a basic main.c
    cat > src/main.c << 'EOF'
#include <stdio.h>

int main() {
    printf("C Learning Experiments Project\n");
    printf("Project: %s\n", PROJECT_NAME);
    printf("Explore the OS concepts in this project!\n");
    return 0;
}
EOF

    # Create a basic .gitignore
    cat > .gitignore << 'EOF'
# Build directory
build/
*.o
os_experiments

# Editor files
.vscode/
.idea/
*.swp
*~

# System files
.DS_Store
Thumbs.db
EOF

    # Create docs/notes.md
    cat > docs/notes.md << EOF
# Learning Notes for $PROJECT_NAME

## Project Goals
- Master C programming
- Understand operating system concepts
- Experiment with system programming

## Experiment Log
- Project Created: $(date '+%Y-%m-%d')
- Project Path: $FULL_PROJECT_DIR
- Concept: Initial Setup
- Key Learnings: Project structure established
EOF

    # Create sample header in include
    cat > include/os_concepts/process_management.h << 'EOF'
#ifndef PROCESS_MANAGEMENT_H
#define PROCESS_MANAGEMENT_H

// Function prototypes for process-related experiments
void demonstrate_fork(void);
void demonstrate_exec(void);

#endif // PROCESS_MANAGEMENT_H
EOF

    # Initialize git repository
    git init > /dev/null 2>&1
    git add . > /dev/null 2>&1
    git commit -m "Initial project setup" > /dev/null 2>&1

    # Print success message
    echo -e "${GREEN}✓ C Learning Experiments Project Created${NC}"
    echo -e "${YELLOW}Project Name:${NC} $PROJECT_NAME"
    echo -e "${YELLOW}Project Location:${NC} $FULL_PROJECT_DIR"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. cd $FULL_PROJECT_DIR"
    echo "2. make"
    echo "3. make run"
}

# Check arguments and call the function
if [ $# -eq 0 ]; then
    create_c_learning_project
elif [ $# -eq 1 ]; then
    create_c_learning_project "$1"
elif [ $# -eq 2 ]; then
    create_c_learning_project "$1" "$2"
else
    echo -e "${RED}Usage:${NC}"
    echo "  $0 [project_name] [project_path]"
    echo "Examples:"
    echo "  $0                   # Creates 'c-learning-experiments' in ~/Projects"
    echo "  $0 my_os_project     # Creates 'my_os_project' in ~/Projects"
    echo "  $0 my_os_project /path/to/projects"
    exit 1
fi