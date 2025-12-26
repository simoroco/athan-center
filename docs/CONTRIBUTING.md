# Contributing to Athan Center

First off, thank you for considering contributing to Athan Center! 🤲

It's people like you that make Athan Center such a great tool for the Muslim community.

## 🌟 Ways to Contribute

- **Report bugs** and issues
- **Suggest new features** or enhancements
- **Improve documentation**
- **Submit pull requests** with bug fixes or new features
- **Help with translations**
- **Share the project** with others

## 🚀 Getting Started

### Prerequisites

- Node.js >= 16.0.0
- npm or yarn
- Git
- (Optional) Docker for containerized development

### Development Setup

1. **Fork the repository**
   ```bash
   # Click the "Fork" button on GitHub
   ```

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/athan-center.git
   cd athan-center
   ```

3. **Install dependencies**
   ```bash
   cd app
   npm install
   ```

4. **Start development server**
   ```bash
   npm run dev
   ```

5. **Access the application**
   - Open `http://localhost:7777` in your browser

## 📝 Development Guidelines

### Code Style

- Use **consistent indentation** (2 spaces for JavaScript/JSON, 4 spaces for HTML)
- Follow **existing code patterns** in the project
- Add **comments** for complex logic
- Keep functions **small and focused**
- Use **meaningful variable names**

### Commit Messages

Follow the conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```bash
feat(api): add next-prayer-text endpoint with French support
fix(ui): correct calendar button weekday display
docs(readme): update API documentation
```

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

**Examples:**
```bash
feature/add-multilingual-api
fix/calendar-weekday-display
docs/update-deployment-guide
```

## 🔄 Pull Request Process

1. **Create a new branch** from `main`
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write clean, documented code
   - Test your changes thoroughly
   - Update documentation if needed

3. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

4. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Open a Pull Request**
   - Go to the original repository
   - Click "New Pull Request"
   - Select your branch
   - Fill in the PR template

### PR Checklist

Before submitting your PR, ensure:

- [ ] Code follows project style guidelines
- [ ] All tests pass (if applicable)
- [ ] Documentation is updated
- [ ] Commit messages are clear and descriptive
- [ ] PR description explains what and why
- [ ] No merge conflicts with main branch

## 🐛 Reporting Bugs

When reporting bugs, please include:

1. **Clear title** describing the issue
2. **Steps to reproduce** the bug
3. **Expected behavior** vs actual behavior
4. **Environment details**:
   - OS (Linux/macOS/Windows)
   - Node.js version
   - Docker version (if applicable)
   - Browser (if UI issue)
5. **Screenshots or logs** if applicable

Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md) when creating an issue.

## 💡 Suggesting Features

We love new ideas! When suggesting features:

1. **Check existing issues** to avoid duplicates
2. **Describe the feature** clearly
3. **Explain the use case** and benefits
4. **Provide examples** if possible

Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md).

## 🧪 Testing

Before submitting changes:

1. **Test locally** on your development environment
2. **Test with Docker** if your changes affect deployment
3. **Test on different platforms** if possible (Linux/macOS/Windows)
4. **Verify API endpoints** work as expected
5. **Check UI responsiveness** on mobile/tablet/desktop

## 📚 Documentation

Good documentation is crucial! When contributing:

- Update **README.md** for user-facing changes
- Update **API.md** for API changes
- Add **inline comments** for complex code
- Update **CHANGELOG.md** with your changes

## 🤝 Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inspiring community for all. Please be respectful and considerate in all interactions.

### Expected Behavior

- Be respectful and inclusive
- Welcome newcomers
- Accept constructive criticism
- Focus on what's best for the community
- Show empathy towards others

### Unacceptable Behavior

- Harassment or discrimination
- Trolling or insulting comments
- Personal or political attacks
- Publishing others' private information
- Any conduct that could be considered inappropriate

## 🎯 Good First Issues

New to the project? Look for issues labeled:
- `good first issue` - Perfect for beginners
- `help wanted` - We need your help!
- `documentation` - Improve our docs

## 💬 Getting Help

Need help? Here's how to reach us:

- **GitHub Issues** - For bugs and feature requests
- **GitHub Discussions** - For questions and general discussion
- **Pull Request Comments** - For code review questions

## 🙏 Recognition

All contributors will be recognized in our README and release notes. Thank you for making Athan Center better!

---

**May Allah reward you for your contributions** 🤲 **جزاك الله خيرا**

By contributing to Athan Center, you agree that your contributions will be licensed under the GPLv3 License.
