"""
Tests for version management functionality
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
from semantic_version import Version
from orchestrator.version_manager import VersionCoordinator


class TestVersionCoordinator:
    """Test suite for VersionCoordinator"""
    
    @pytest.fixture
    def coordinator(self, tmp_path):
        """Create a VersionCoordinator with test configuration"""
        config_file = tmp_path / "test_config.yaml"
        config_file.write_text("""
repositories:
  lib-a:
    url: git@github.com:test/lib-a.git
    version: 1.0.0
    type: library
    dependencies: []
  
  service-b:
    url: git@github.com:test/service-b.git
    version: 2.0.0
    type: service
    dependencies:
      - name: lib-a
        version: "^1.0.0"
        type: compile
  
  app-c:
    url: git@github.com:test/app-c.git
    version: 3.0.0
    type: application
    dependencies:
      - name: service-b
        version: "^2.0.0"
        type: runtime
      - name: lib-a
        version: "^1.0.0"
        type: compile

dependency_rules:
  resolution: highest-compatible
  lock_strategy: conservative
  update_policy: explicit
""")
        return VersionCoordinator(str(config_file))
    
    def test_initialization(self, coordinator):
        """Test coordinator initialization"""
        assert coordinator.repos is not None
        assert 'repositories' in coordinator.repos
        assert len(coordinator.repos['repositories']) == 3
    
    def test_build_dependency_graph(self, coordinator):
        """Test dependency graph building"""
        graph = coordinator.dependency_graph
        
        # Check that service-b depends on lib-a
        assert 'service-b' in graph['lib-a']
        
        # Check that app-c depends on both
        assert 'app-c' in graph['lib-a']
        assert 'app-c' in graph['service-b']
    
    @patch('subprocess.check_output')
    def test_get_current_version(self, mock_subprocess, coordinator):
        """Test getting current version from git tags"""
        mock_subprocess.return_value = "v1.2.3\n"
        
        version = coordinator.get_current_version("lib-a")
        
        assert version == Version("1.2.3")
        mock_subprocess.assert_called_once()
    
    @patch('subprocess.check_output')
    def test_get_current_version_no_tags(self, mock_subprocess, coordinator):
        """Test getting version when no tags exist"""
        mock_subprocess.side_effect = Exception("No tags")
        
        version = coordinator.get_current_version("lib-a")
        
        assert version == Version("0.1.0")
    
    def test_bump_version_patch(self, coordinator):
        """Test patch version bump"""
        current = Version("1.2.3")
        new = coordinator.bump_version(current, "patch")
        
        assert new == Version("1.2.4")
    
    def test_bump_version_minor(self, coordinator):
        """Test minor version bump"""
        current = Version("1.2.3")
        new = coordinator.bump_version(current, "minor")
        
        assert new == Version("1.3.0")
    
    def test_bump_version_major(self, coordinator):
        """Test major version bump"""
        current = Version("1.2.3")
        new = coordinator.bump_version(current, "major")
        
        assert new == Version("2.0.0")
    
    @patch.object(VersionCoordinator, 'get_current_version')
    def test_coordinate_release(self, mock_get_version, coordinator):
        """Test release coordination planning"""
        mock_get_version.return_value = Version("1.0.0")
        
        plan = coordinator.coordinate_release("lib-a", "minor")
        
        assert plan['source']['repo'] == "lib-a"
        assert plan['source']['new_version'] == "1.1.0"
        assert plan['source']['bump_type'] == "minor"
        
        # Check affected repositories
        affected_repos = [r['repo'] for r in plan['affected']]
        assert 'service-b' in affected_repos
    
    def test_coordinate_release_invalid_repo(self, coordinator):
        """Test release coordination with invalid repository"""
        with pytest.raises(ValueError) as exc_info:
            coordinator.coordinate_release("invalid-repo", "patch")
        
        assert "not found" in str(exc_info.value)
    
    @patch('subprocess.run')
    def test_tag_and_push(self, mock_run, coordinator):
        """Test git tag creation and push"""
        coordinator._tag_and_push("lib-a", "1.2.3")
        
        # Should make two calls: one for tag, one for push
        assert mock_run.call_count == 2
        
        # Check tag command
        tag_call = mock_run.call_args_list[0]
        assert "tag -a v1.2.3" in tag_call[0][0]
        
        # Check push command
        push_call = mock_run.call_args_list[1]
        assert "push origin v1.2.3" in push_call[0][0]
    
    def test_validate_versions(self, coordinator):
        """Test version validation across repositories"""
        with patch.object(coordinator, 'get_current_version') as mock_get:
            # Simulate version mismatch
            mock_get.side_effect = [
                Version("1.0.0"),  # lib-a actual
                Version("2.1.0"),  # service-b actual (mismatch)
                Version("3.0.0"),  # app-c actual
                Version("1.0.0"),  # lib-a for dependency check
                Version("2.1.0"),  # service-b for dependency check
            ]
            
            result = coordinator.validate_versions()
            
            assert not result['valid']
            assert len(result['issues']) > 0
            
            # Check for version mismatch detection
            issues = result['issues']
            version_issues = [i for i in issues if i['issue'] == 'version_mismatch']
            assert len(version_issues) == 1
            assert version_issues[0]['repo'] == 'service-b'


class TestVersionBumping:
    """Test version bumping logic"""
    
    def test_semantic_version_parsing(self):
        """Test semantic version parsing"""
        version = Version("1.2.3-alpha.1+build.456")
        
        assert version.major == 1
        assert version.minor == 2
        assert version.patch == 3
        assert len(version.prerelease) == 2
        assert version.build == ["build", "456"]
    
    def test_version_comparison(self):
        """Test version comparison"""
        v1 = Version("1.0.0")
        v2 = Version("1.0.1")
        v3 = Version("2.0.0")
        
        assert v1 < v2 < v3
        assert v3 > v2 > v1
        assert v1 != v2
    
    def test_version_range_matching(self):
        """Test version range matching with Spec"""
        from semantic_version import Spec
        
        spec = Spec("^1.0.0")
        
        assert spec.match(Version("1.0.0"))
        assert spec.match(Version("1.9.9"))
        assert not spec.match(Version("2.0.0"))
        assert not spec.match(Version("0.9.9"))