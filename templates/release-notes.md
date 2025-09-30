# Release Notes Template

## Version {{VERSION}} - {{DATE}}

### 🎯 Release Overview

Brief description of this release's main theme or focus.

### ✨ New Features

- **Feature Name**: Brief description of the feature
  - Sub-point with more details
  - Impact or benefit to users

### 🐛 Bug Fixes

- **Issue #XX**: Description of the bug that was fixed
- **Issue #YY**: Another bug fix description

### 🔧 Improvements

- **Performance**: Improved X by Y%
- **Refactoring**: Cleaned up module Z
- **Dependencies**: Updated package A to version B

### 💔 Breaking Changes

> ⚠️ **Action Required**

- **API Change**: Old endpoint deprecated, use new endpoint
- **Configuration**: New required field in config file
- **Migration Steps**:
  1. Step one
  2. Step two

### 📦 Dependency Updates

| Package | Old Version | New Version | Notes |
|---------|------------|-------------|-------|
| example-lib | 1.2.3 | 1.3.0 | Security patches |
| framework | 2.0.0 | 2.1.0 | New features |

### 🔄 Repository Coordination

#### Repositories Included in This Release

- `backend` - v{{BACKEND_VERSION}}
- `frontend` - v{{FRONTEND_VERSION}}
- `auth-service` - v{{AUTH_VERSION}}

#### Dependency Chain Updates

```
backend (1.2.0 → 1.3.0)
  └─> frontend (2.1.0 → 2.1.1)
  └─> monitoring (1.0.5 → 1.0.6)
```

### 📝 Migration Guide

#### From v{{PREVIOUS_VERSION}}

1. **Database Migrations**
   ```sql
   -- Run migration script
   ALTER TABLE users ADD COLUMN feature_flag BOOLEAN DEFAULT false;
   ```

2. **Configuration Updates**
   ```yaml
   # Add to config.yaml
   new_feature:
     enabled: true
     threshold: 100
   ```

3. **API Changes**
   - Old: `GET /api/v1/resource`
   - New: `GET /api/v2/resource`

### 🧪 Testing

#### Test Coverage
- Unit Tests: {{UNIT_COVERAGE}}%
- Integration Tests: {{INTEGRATION_COVERAGE}}%
- E2E Tests: {{E2E_COVERAGE}}%

#### Performance Benchmarks
- Response Time: {{RESPONSE_TIME}}ms ({{RESPONSE_CHANGE}}%)
- Throughput: {{THROUGHPUT}} req/s ({{THROUGHPUT_CHANGE}}%)
- Memory Usage: {{MEMORY}}MB ({{MEMORY_CHANGE}}%)

### 📊 Deployment Checklist

- [ ] All tests passing
- [ ] Documentation updated
- [ ] Database migrations prepared
- [ ] Environment variables configured
- [ ] Monitoring alerts configured
- [ ] Rollback plan documented
- [ ] Load testing completed
- [ ] Security scan completed

### 🚀 Deployment Instructions

#### Production Deployment

```bash
# 1. Pull latest octo updates
git pull origin main

# 2. Prepare release
./scripts/release/prepare-release.sh v{{VERSION}} all

# 3. Run deployment
./scripts/release/coordinate-release.sh v{{VERSION}} false

# 4. Verify deployment
./scripts/orchestrate.py health
```

#### Rollback Procedure

If issues are encountered:

```bash
# Emergency rollback
./scripts/release/rollback-release.sh v{{VERSION}} v{{PREVIOUS_VERSION}} all
```

### 👥 Contributors

Thanks to everyone who contributed to this release:

- @contributor1 - Feature X implementation
- @contributor2 - Bug fixes and testing
- @contributor3 - Documentation updates

### 📚 Documentation

- [API Documentation](./docs/api.md)
- [Configuration Guide](./docs/configuration.md)
- [Architecture Overview](./docs/architecture.md)
- [Troubleshooting Guide](./docs/troubleshooting.md)

### 🔗 Related Links

- [GitHub Milestone](https://github.com/org/repo/milestone/X)
- [Project Board](https://github.com/orgs/org/projects/Y)
- [Security Advisory](https://github.com/org/repo/security/advisories)

### 📅 Timeline

- **Code Freeze**: {{FREEZE_DATE}}
- **Testing Complete**: {{TEST_DATE}}
- **Staging Deployment**: {{STAGING_DATE}}
- **Production Deployment**: {{PROD_DATE}}

### ⚠️ Known Issues

- Issue #123: Minor UI glitch in specific browser versions
- Issue #456: Performance degradation with >10000 records (workaround available)

### 🔮 Next Release Preview

The next release (v{{NEXT_VERSION}}) is planned for {{NEXT_RELEASE_DATE}} and will include:

- Major feature: New authentication system
- Performance improvements
- Additional API endpoints

---

## Support

For questions or issues related to this release:

- Create an issue: [GitHub Issues](https://github.com/org/repo/issues)
- Contact team: team@example.com
- Documentation: [Release Documentation](./docs/releases/v{{VERSION}})

---

*Released by Repo Orchestrator v{{OCTO_VERSION}}*