# Security Policy

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
|---------|--------------------|
| 1.x.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

**Please DO NOT file a public issue for security vulnerabilities.**

Instead, please send an email to: **<dev@frugan.it>**

Include the following information:

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggested fixes (if available)

### What to Expect

1. **Acknowledgment**: We will acknowledge receipt within 48 hours
2. **Assessment**: We will assess the vulnerability within 5 business days
3. **Resolution**: We will work to resolve critical issues within 30 days
4. **Disclosure**: We will coordinate with you on responsible disclosure

### Responsible Disclosure

We believe in responsible disclosure. We ask that you:

- Give us reasonable time to investigate and fix the issue
- Do not publicly disclose the vulnerability until we've had a chance to fix it
- Do not exploit the vulnerability for malicious purposes

### Security Best Practices

When running ConvSync:

1. **No network**: OCR and conversion are fully local. Run the container with
   `network_mode: none` (the default in `docker-compose.yml`), so documents
   cannot leave the machine even through a compromised dependency
2. **Sensitive data**: the documents and the Markdown generated from them
   (`_md/`, `_ocr/`) usually hold personal or tax data — keep them out of
   version control and off shared storage
3. **Agents**: if LLM agents read `_md/`, remember that whatever they read may
   be sent to their model provider
4. **Untrusted PDFs**: the image parses them with Ghostscript, poppler and
   pikepdf. Keep the image up to date (the monthly rebuild pulls the Debian
   security fixes) and do not mount anything else writable into it

## Security Contact

For security-related questions or concerns:

- Email: <dev@frugan.it>
- GitHub: [@frugan-dev](https://github.com/frugan-dev)

## Acknowledgments

We appreciate the security research community's efforts in responsibly disclosing vulnerabilities. Security researchers who help us improve this project will be acknowledged in our security advisories (with their permission).
