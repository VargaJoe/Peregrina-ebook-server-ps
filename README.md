# Peregrina Ebook Server (PowerShell)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Overview

Peregrina is an experimental ebook server built entirely with PowerShell. This project demonstrates PowerShell's capabilities beyond traditional scripting by implementing a fully functional web server for digital document management and delivery.

> **Note:** This implementation is designed for educational and research purposes. It is not recommended for production environments or exposed networks.

## Features

- **Multi-format Support:** Handles various document formats:
  - EPUB (Electronic Publications)
  - PDF (Portable Document Format)
  - CBZ (Comic Book ZIP)
  - Plain text files
  - Image files
  
- **Flexible Category Configuration:** Define custom library categories via simple JSON configuration
  
- **MVC-like Architecture:** Uses a pattern similar to Model-View-Controller for clean separation of concerns
  
- **Custom Template Engine:** Uses `.pshtml` files, a custom PowerShell HTML template format created specifically for this project
  
- **Docker Support:** Run in containerized environments for isolation and portability

## Getting Started

### Prerequisites

- PowerShell 5.1 or higher
- Windows, or PowerShell Core on Linux/macOS

### Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/Peregrina-ebook-server-ps.git
   cd Peregrina-ebook-server-ps
   ```

2. Configure your library:
   Edit `src/settings.json` to specify your document folders:
   ```json
   {
     "booksPaths": ["D:/ebooks", "E:/literature"],
     "comicsPaths": ["D:/comics", "E:/manga"],
     "documentsPaths": ["D:/documents"]
   }
   ```
   
   Each category will appear as a main section on the homepage with corresponding URL routes:
   - `booksPaths` → `/books`
   - `comicsPaths` → `/comics`

3. Launch the server:
   ```powershell
   cd src
   .\program.ps1
   ```

4. Access the server at:
   - `http://localhost:8888` (HTTP)
   - `https://localhost:443` (HTTPS, requires certificate configuration)

### Docker Deployment

For containerized deployment, see the [Docker documentation](./info/docker.md).

## Technical Architecture

### Request Handling

The server uses `System.Net.HttpListener` to process incoming requests through a chain of specialized handlers:

1. **Static Request Handler:** Serves static files (CSS, JavaScript, images)
2. **Controller Request Handler:** Processes MVC-style controller requests
3. **Peregrina Request Handler:** Manages ebook-specific routing and content delivery
4. **Error Request Handler:** Provides fallback error responses

### View Rendering

Dynamic pages are rendered using custom `.pshtml` template files, which combine HTML with embedded PowerShell code blocks. This custom templating format was created specifically for this project and draws inspiration from ASP.NET's Razor syntax but utilizes PowerShell scripting instead. The templating system allows for:

- Seamless integration of PowerShell code within HTML markup
- Dynamic content generation based on server-side data
- Reusable template components
- Conditional rendering and loops

### File Format Handling

Each supported document type has dedicated model objects that handle:
- Metadata extraction
- Content rendering
- Navigation structures
- Thumbnail/cover generation

## URL Structure

For information about URL patterns and routing, see [URL Types Documentation](./info/url-types.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
