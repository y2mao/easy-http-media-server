package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"io/fs"
	"log"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// FileInfo represents file information for directory listing
type FileInfo struct {
	Name        string
	Path        string
	Size        int64
	ModTime     time.Time
	IsDir       bool
	MimeType    string
	EncodedPath string
}

// GetFileIcon returns the appropriate icon for the file type
func (f FileInfo) GetFileIcon() string {
	if f.IsDir {
		return "📁"
	}

	ext := strings.ToLower(filepath.Ext(f.Name))
	if strings.HasPrefix(f.MimeType, "video/") || ext == ".mp4" || ext == ".avi" ||
		ext == ".mkv" || ext == ".mov" || ext == ".wmv" || ext == ".flv" || ext == ".webm" {
		return "🎬"
	}

	if strings.HasPrefix(f.MimeType, "audio/") || ext == ".mp3" || ext == ".wav" ||
		ext == ".flac" || ext == ".aac" || ext == ".ogg" || ext == ".m4a" {
		return "🎵"
	}

	if strings.HasPrefix(f.MimeType, "image/") || ext == ".jpg" || ext == ".jpeg" ||
		ext == ".png" || ext == ".gif" || ext == ".bmp" || ext == ".webp" {
		return "🖼️"
	}

	return "📄"
}

// GetFileClass returns the CSS class for the file type
func (f FileInfo) GetFileClass() string {
	if f.IsDir {
		return "directory"
	}

	ext := strings.ToLower(filepath.Ext(f.Name))
	if strings.HasPrefix(f.MimeType, "video/") || ext == ".mp4" || ext == ".avi" ||
		ext == ".mkv" || ext == ".mov" || ext == ".wmv" || ext == ".flv" || ext == ".webm" {
		return "video-file"
	}

	if strings.HasPrefix(f.MimeType, "audio/") || ext == ".mp3" || ext == ".wav" ||
		ext == ".flac" || ext == ".aac" || ext == ".ogg" || ext == ".m4a" {
		return "audio-file"
	}

	if strings.HasPrefix(f.MimeType, "image/") || ext == ".jpg" || ext == ".jpeg" ||
		ext == ".png" || ext == ".gif" || ext == ".bmp" || ext == ".webp" {
		return "image-file"
	}

	return ""
}

// GetFormattedSize returns the file size formatted in MB
func (f FileInfo) GetFormattedSize() string {
	sizeInMB := float64(f.Size) / 1048576
	return fmt.Sprintf("%.2f", sizeInMB)
}

// DirectoryData holds data for directory listing template
type DirectoryData struct {
	Path       string
	ParentPath string
	Files      []FileInfo
	ServerName string
}

// MediaServer represents the HTTP media server
type MediaServer struct {
	config   *Config
	template *template.Template
}

// NewMediaServer creates a new media server instance
func NewMediaServer(config *Config) *MediaServer {
	tmpl := template.Must(template.New("directory").Parse(directoryTemplate))
	return &MediaServer{
		config:   config,
		template: tmpl,
	}
}

// Start starts the HTTP server
func (s *MediaServer) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleRequest)
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/api/info", s.handleAPIInfo)

	addr := fmt.Sprintf("%s:%d", s.config.Server.Host, s.config.Server.Port)
	log.Printf("Starting media server on %s", addr)
	log.Printf("Serving directory: %s", s.config.Media.Directory)
	log.Printf("Health check available at: http://%s/health", addr)
	log.Printf("API info available at: http://%s/api/info", addr)

	server := &http.Server{
		Addr:         addr,
		Handler:      s.corsMiddleware(s.loggingMiddleware(mux)),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	return server.ListenAndServe()
}

// corsMiddleware adds CORS headers for better compatibility
func (s *MediaServer) corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Range")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// loggingMiddleware logs all HTTP requests
func (s *MediaServer) loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Create a response writer wrapper to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: 200}

		next.ServeHTTP(wrapped, r)

		duration := time.Since(start)
		log.Printf("%s %s %s - %d - %v - %s",
			r.Method,
			r.URL.Path,
			r.RemoteAddr,
			wrapped.statusCode,
			duration,
			r.UserAgent())
	})
}

// responseWriter wraps http.ResponseWriter to capture status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// handleHealth provides a health check endpoint
func (s *MediaServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check if media directory is accessible
	_, err := os.Stat(s.config.Media.Directory)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, `{"status":"unhealthy","error":"media directory not accessible: %s"}`, err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"status":"healthy","timestamp":"%s","media_directory":"%s"}`,
		time.Now().Format(time.RFC3339), s.config.Media.Directory)
}

// handleAPIInfo provides server information
func (s *MediaServer) handleAPIInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	info := map[string]interface{}{
		"name":            "HTTP Media Server",
		"version":         "2.0.0",
		"media_directory": s.config.Media.Directory,
		"server_time":     time.Now().Format(time.RFC3339),
		"endpoints": map[string]string{
			"health":   "/health",
			"api_info": "/api/info",
			"browse":   "/",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(info); err != nil {
		log.Printf("Error encoding API info: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// handleRequest handles all HTTP requests
func (s *MediaServer) handleRequest(w http.ResponseWriter, r *http.Request) {

	// Decode URL path
	decodedPath, err := url.QueryUnescape(r.URL.Path)
	if err != nil {
		http.Error(w, "Invalid URL path", http.StatusBadRequest)
		return
	}

	// Clean and join with media directory
	cleanPath := path.Clean(decodedPath)
	if cleanPath == "." {
		cleanPath = "/"
	}

	fullPath := filepath.Join(s.config.Media.Directory, cleanPath)

	// Security check: ensure path is within media directory
	absMediaDir, err := filepath.Abs(s.config.Media.Directory)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	absFullPath, err := filepath.Abs(fullPath)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	if !strings.HasPrefix(absFullPath, absMediaDir) {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	// Check if file/directory exists
	fileInfo, err := os.Stat(fullPath)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("File not found: %s (requested: %s)", fullPath, r.URL.Path)
			http.NotFound(w, r)
		} else {
			log.Printf("Error accessing file %s: %v", fullPath, err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
		}
		return
	}

	if fileInfo.IsDir() {
		s.serveDirectory(w, r, fullPath, cleanPath)
	} else {
		s.serveFile(w, r, fullPath, fileInfo)
	}
}

// serveDirectory serves directory listing
func (s *MediaServer) serveDirectory(w http.ResponseWriter, r *http.Request, fullPath, urlPath string) {
	entries, err := os.ReadDir(fullPath)
	if err != nil {
		http.Error(w, "Unable to read directory", http.StatusInternalServerError)
		return
	}

	var files []FileInfo

	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue
		}

		// Skip hidden files
		if strings.HasPrefix(info.Name(), ".") {
			continue
		}

		filePath := path.Join(urlPath, info.Name())
		mimeType := ""

		if !info.IsDir() {
			mimeType = mime.TypeByExtension(filepath.Ext(info.Name()))
			if mimeType == "" {
				mimeType = "application/octet-stream"
			}
		}

		files = append(files, FileInfo{
			Name:        info.Name(),
			Path:        filePath,
			Size:        info.Size(),
			ModTime:     info.ModTime(),
			IsDir:       info.IsDir(),
			MimeType:    mimeType,
			EncodedPath: url.PathEscape(filePath),
		})
	}

	// Sort files: directories first, then by name
	sort.Slice(files, func(i, j int) bool {
		if files[i].IsDir != files[j].IsDir {
			return files[i].IsDir
		}
		return strings.ToLower(files[i].Name) < strings.ToLower(files[j].Name)
	})

	// Prepare template data
	data := DirectoryData{
		Path:       urlPath,
		Files:      files,
		ServerName: "HTTP Media Server",
	}

	// Add parent directory link if not at root
	if urlPath != "/" {
		data.ParentPath = path.Dir(urlPath)
		if data.ParentPath == "." {
			data.ParentPath = "/"
		}
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := s.template.Execute(w, data); err != nil {
		log.Printf("Template execution error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// serveFile serves individual files with proper headers for media streaming
func (s *MediaServer) serveFile(w http.ResponseWriter, r *http.Request, fullPath string, fileInfo fs.FileInfo) {
	file, err := os.Open(fullPath)
	if err != nil {
		http.Error(w, "Unable to open file", http.StatusInternalServerError)
		return
	}
	defer file.Close()

	// Set content type
	contentType := mime.TypeByExtension(filepath.Ext(fullPath))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	w.Header().Set("Content-Type", contentType)

	// Set headers for better media player compatibility
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.Header().Set("Content-Length", fmt.Sprintf("%d", fileInfo.Size()))

	// Set filename for download
	filename := filepath.Base(fullPath)
	w.Header().Set("Content-Disposition", fmt.Sprintf("inline; filename=\"%s\"", filename))

	// Serve file with range support for media streaming
	http.ServeContent(w, r, filename, fileInfo.ModTime(), file)
}

// HTML template for directory listing
const directoryTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.ServerName}} - {{.Path}}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .header h1 {
            margin: 0;
            font-size: 24px;
        }
        .path {
            margin: 10px 0 0 0;
            font-size: 14px;
            opacity: 0.9;
        }
        .file-list {
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .file-item {
            display: block;
            padding: 15px 20px;
            text-decoration: none;
            color: #333;
            border-bottom: 1px solid #eee;
            transition: background-color 0.2s;
        }
        .file-item:hover {
            background-color: #f8f9fa;
        }
        .file-item:last-child {
            border-bottom: none;
        }
        .file-icon {
            display: inline-block;
            width: 20px;
            margin-right: 10px;
            text-align: center;
        }
        .file-name {
            font-weight: 500;
        }
        .file-info {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }
        .parent-link {
            background-color: #e3f2fd;
            font-weight: bold;
        }
        .directory {
            color: #1976d2;
        }
        .video-file {
            color: #d32f2f;
        }
        .audio-file {
            color: #388e3c;
        }
        .image-file {
            color: #f57c00;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>{{.ServerName}}</h1>
        <div class="path">{{.Path}}</div>
    </div>

    <div class="file-list">
        {{if .ParentPath}}
        <a href="{{.ParentPath}}" class="file-item parent-link">
            <span class="file-icon">↰</span>
            <div class="file-name">.. (Parent Directory)</div>
        </a>
        {{end}}

        {{range .Files}}
        <a href="{{.EncodedPath}}" class="file-item {{if .IsDir}}directory{{else}}{{.GetFileClass}}{{end}}">
            <span class="file-icon">
                {{.GetFileIcon}}
            </span>
            <div class="file-name">{{.Name}}</div>
            {{if not .IsDir}}
            <div class="file-info">
                {{if .MimeType}}{{.MimeType}} • {{end}}{{.GetFormattedSize}} MB • {{.ModTime.Format "2006-01-02 15:04:05"}}
            </div>
            {{end}}
        </a>
        {{end}}
    </div>
</body>
</html>`
