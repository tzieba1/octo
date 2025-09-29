#!/bin/bash
# scripts/rollback/emergency-rollback.sh

perform_rollback() {
    local rollback_point=$1
    
    # Create rollback branch
    git checkout -b rollback/$(date +%Y%m%d-%H%M%S)
    
    # Save current state
    git stash create "Pre-rollback state"
    
    # For each repository
    for repo in $(ls repos/); do
        echo "Rolling back $repo to $rollback_point"
        
        # Find corresponding version
        version=$(git notes --ref=releases show $rollback_point | jq -r ".$repo")
        
        # Perform rollback
        git -C repos/$repo checkout tags/$version -b rollback-$version
        
        # Update deployment configs
        yq eval ".repositories.$repo.version = \"$version\"" -i repositories.yaml
    done
    
    # Commit rollback state
    git add repositories.yaml
    git commit -m "ROLLBACK: System state to $rollback_point"
}