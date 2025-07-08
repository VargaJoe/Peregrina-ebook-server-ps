// PDF.js viewer implementation for Peregrina

// Global variables
let pdfDoc = null;
let pageNum = 1;
let pageRendering = false;
let pageNumPending = null;
let scale = 1.5;
let canvas = null;
let ctx = null;

// Debugging function
function debugLog(message) {
  console.log(`[PDF Viewer] ${message}`);
  if (document.getElementById('error-message')) {
    document.getElementById('error-message').textContent += `\n${message}`;
    document.getElementById('error-container').style.display = 'block';
  }
}

// Initialize the viewer with the PDF URL and starting page
function initPdfViewer(pdfUrl, initialPage = 1) {
  debugLog(`Initializing PDF viewer with URL: ${pdfUrl}, page: ${initialPage}`);
  
  canvas = document.getElementById('pdf-canvas');
  if (!canvas) {
    debugLog("Error: Could not find canvas element!");
    return;
  }
  
  ctx = canvas.getContext('2d');
  pageNum = parseInt(initialPage) || 1;
  
  // Update page navigation controls
  document.getElementById('page-num').textContent = pageNum;
  
  // Check if PDF.js is available
  if (typeof pdfjsLib === 'undefined') {
    debugLog("Error: PDF.js library not loaded!");
    return;
  }
  
  debugLog("Loading PDF document...");
  
  // Load the PDF
  pdfjsLib.getDocument(pdfUrl).promise.then(function(pdfDoc_) {
    debugLog(`PDF loaded successfully with ${pdfDoc_.numPages} pages`);
    pdfDoc = pdfDoc_;
    document.getElementById('page-count').textContent = pdfDoc.numPages;
    
    // Initial page render
    renderPage(pageNum);
    
    // Enable controls once PDF is loaded
    document.getElementById('prev').disabled = false;
    document.getElementById('next').disabled = false;
    document.getElementById('zoom-in').disabled = false;
    document.getElementById('zoom-out').disabled = false;
  }).catch(function(error) {
    debugLog(`Error loading PDF: ${error.message}`);
    console.error('Error loading PDF:', error);
    document.getElementById('error-message').textContent = 
      'Error loading PDF: ' + error.message;
    document.getElementById('error-container').style.display = 'block';
  });
}

// Render the specified page
function renderPage(num) {
  pageRendering = true;
  
  // Update page display
  document.getElementById('page-num').textContent = num;
  
  // Update URL with the current page
  updateUrlWithPage(num);
  
  // Get page from PDF
  pdfDoc.getPage(num).then(function(page) {
    const viewport = page.getViewport({ scale: scale });
    canvas.height = viewport.height;
    canvas.width = viewport.width;
    
    // Render PDF page into canvas context
    const renderContext = {
      canvasContext: ctx,
      viewport: viewport
    };
    
    const renderTask = page.render(renderContext);
    
    // Wait for rendering to finish
    renderTask.promise.then(function() {
      pageRendering = false;
      
      // If another page rendering is pending, execute it
      if (pageNumPending !== null) {
        renderPage(pageNumPending);
        pageNumPending = null;
      }
    });
  });
}

// Queue rendering of a page
function queueRenderPage(num) {
  if (pageRendering) {
    pageNumPending = num;
  } else {
    renderPage(num);
  }
}

// Go to previous page
function onPrevPage() {
  if (pageNum <= 1) {
    return;
  }
  pageNum--;
  queueRenderPage(pageNum);
}

// Go to next page
function onNextPage() {
  if (pageNum >= pdfDoc.numPages) {
    return;
  }
  pageNum++;
  queueRenderPage(pageNum);
}

// Zoom in the PDF
function zoomIn() {
  scale += 0.25;
  renderPage(pageNum);
}

// Zoom out the PDF
function zoomOut() {
  if (scale > 0.5) {
    scale -= 0.25;
    renderPage(pageNum);
  }
}

// Update URL when changing pages
function updateUrlWithPage(pageNum) {
  const url = new URL(window.location.href);
  url.searchParams.set('page', pageNum);
  window.history.replaceState({}, '', url.toString());
}

// Go to specific page
function goToPage() {
  const input = document.getElementById('page-input');
  const pageNumber = parseInt(input.value);
  
  if (isNaN(pageNumber) || pageNumber < 1 || pageNumber > pdfDoc.numPages) {
    alert(`Please enter a valid page number between 1 and ${pdfDoc.numPages}`);
    return;
  }
  
  pageNum = pageNumber;
  queueRenderPage(pageNum);
}

// Add event listeners after the page loads
document.addEventListener('DOMContentLoaded', function() {
  // We'll set up the event listeners in the HTML
});