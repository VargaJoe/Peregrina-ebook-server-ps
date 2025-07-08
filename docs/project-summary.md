# Peregrina Ebook Server - Project Summary

## Overview

Peregrina is an experimental PowerShell-based ebook server that demonstrates the capabilities of building a sophisticated web application using PowerShell with an MVC-like architecture. The project serves as both a functional ebook reader and a showcase for PowerShell's web development potential.

## Architecture

### Core Design Principles
- **MVC Pattern**: Clear separation between Models, Views, and Controllers
- **Modular Design**: Component-based architecture with pluggable request handlers
- **Dual Mode Operation**: Both synchronous and asynchronous request processing
- **File-based Configuration**: JSON settings for easy customization
- **Container Ready**: Docker support for deployment

### Key Components

#### 1. Web Server Core
- **Entry Points**: 
  - `start.ps1` - Synchronous web server
  - `start-async.ps1` - Asynchronous web server with better performance
- **HTTP Foundation**: Built on .NET's `System.Net.HttpListener`
- **Port Management**: Automatic port detection and admin privilege handling
- **Request Routing**: Sequential handler chain with early termination

#### 2. Request Processing Pipeline
The server processes requests through a sequential pipeline:

1. **StaticRequestObject** - Serves static files (CSS, JS, images)
2. **ControllerRequestObject** - Handles controller-based routes
3. **peregrinaRequestObject** - Main ebook functionality router
4. **ErrorRequestObject** - 404 and error handling

#### 3. Content Type Support
- **PDF Documents** - Full document viewing with PDF.js integration
- **EPUB Ebooks** - XHTML content extraction and rendering
- **CBZ/ZIP Comics** - Image extraction and sequential viewing
- **Images** - Direct image serving with thumbnail generation
- **Text Files** - Plain text rendering

#### 4. Model System
- **Dynamic Loading** - Models loaded based on file type detection
- **Content Models** - Specialized models for each content type
- **Category Models** - Folder and index browsing
- **Caching Models** - Cover and thumbnail management

#### 5. View System
- **Custom Templating** - `.pshtml` files with PowerShell evaluation
- **Responsive Design** - Modern CSS with mobile support
- **Content-Specific Views** - Tailored interfaces for each content type
- **Navigation** - Breadcrumb and category browsing

#### 6. Caching Strategy
- **Cover Cache** - Extracted book/comic covers stored in `./cache/covers/`
- **Thumbnail Cache** - Generated thumbnails in `./cache/thumbnails/`
- **Temporary Files** - Processing workspace in `./cache/tmp/`
- **Performance** - Configurable caching enables/disables per type

## File Structure

```
src/
├── start.ps1                    # Synchronous server entry point
├── start-async.ps1             # Asynchronous server entry point
├── program.ps1                 # Main synchronous server logic
├── program-async.ps1           # Main asynchronous server logic
├── settings.json              # Server configuration
├── controllers/               # MVC Controllers
├── models/                    # Data models for content types
├── views/                     # HTML templates (.pshtml)
├── requestHandler/            # Request processing pipeline
├── utils/                     # Helper functions and utilities
├── actions/                   # Specialized action handlers
├── style/                     # CSS stylesheets
├── scripts/                   # Client-side JavaScript
├── books/                     # PDF and EPUB content
├── comics/                    # CBZ/ZIP comic content
└── cache/                     # Generated covers and thumbnails
```

## Configuration

The server is configured through `settings.json`:

- **Content Paths**: Configurable directories for books, comics, and files
- **User Management**: Basic user authentication (placeholder)
- **Cache Settings**: Enable/disable cover and thumbnail caching
- **File Type Mapping**: Extensions to content type mapping
- **Folder Structure**: Cache and temporary directory configuration

## Performance Features

### Asynchronous Mode
- **Non-blocking I/O**: Async request processing with callback system
- **Concurrent Requests**: Multiple simultaneous connections
- **Resource Management**: Request cancellation and cleanup
- **Debug Logging**: Comprehensive logging for troubleshooting

### Caching System
- **Smart Caching**: Generates covers and thumbnails on-demand
- **Storage Efficiency**: Configurable cache locations
- **Performance Monitoring**: Request counting and error tracking

## Technical Innovation

### PowerShell Web Development
This project demonstrates advanced PowerShell capabilities:
- **Object-Oriented Design**: Extensive use of PowerShell classes
- **HTTP Protocol Handling**: Direct .NET framework integration
- **Template Processing**: Custom HTML templating with PowerShell evaluation
- **Binary Data Processing**: Image and document manipulation
- **Async Programming**: PowerShell async patterns and callbacks

### Cross-Platform Considerations
- **PowerShell Core**: Compatible with modern PowerShell versions
- **Docker Support**: Containerized deployment options
- **Windows Integration**: Native Windows PowerShell compatibility

## Use Cases

1. **Personal Library Server**: Self-hosted ebook and comic collection
2. **Educational Tool**: Demonstrates PowerShell web development techniques
3. **Prototype Platform**: Base for building PowerShell web applications
4. **Content Management**: Organized browsing of digital content collections

## Future Potential

The architecture supports expansion into:
- Advanced user authentication
- Content management features
- API endpoints for mobile apps
- Enhanced search capabilities
- Social features (reading lists, reviews)
- Integration with external content sources

## Conclusion

Peregrina showcases PowerShell's capability as a web development platform, proving that complex web applications can be built using familiar Windows scripting tools. The project serves as both a functional ebook server and a learning resource for PowerShell-based web development.
