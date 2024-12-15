
# SimpleFetch: A Bash-based HTTP Request Tool  

**SimpleFetch** is a lightweight HTTP/HTTPS request tool developed using Bash scripting. It simplifies HTTP requests, showcasing key Operating System concepts like threading, process management, and file handling.  

## Features  
- **GET/POST Requests**: Support for basic HTTP/HTTPS requests.  
- **Caching**: Speeds up repeated requests by storing responses.  
- **Log Management**: Automated log rotation for organized logs.  
- **System Monitoring**: Tracks memory usage and CPU load during execution.  
- **Concurrency**: Handles multiple requests simultaneously using Bash background processes.  

## How It Works  
1. **Input Parsing**: Accepts HTTP method, URL, and optional flags (e.g., `-c` for caching).  
2. **Request Handling**: Constructs and sends HTTP requests via `nc` or `openssl`.  
3. **Caching**: Stores responses for repeated requests to improve performance.  
4. **Logging**: Tracks system metrics and request logs with automatic size management.  

### Example Usage  
- Basic GET request:  
  ```bash  
  ./simplefetch.sh GET http://example.com  
  ```  
- GET request with caching:  
  ```bash  
  ./simplefetch.sh GET http://example.com -c  
  ```  
- Concurrent requests:  
  ```bash  
  ./simplefetch.sh GET http://example.com & ./simplefetch.sh GET http://example.org &  
  ```  

## Key Learnings  
- Demonstrates threading, file handling, and resource management in a real-world scenario.  
- Provides a simple, beginner-friendly alternative to tools like `curl` and `wget`.  

## Conclusion  
**SimpleFetch** is a practical tool for understanding Operating System concepts through hands-on Bash scripting. It bridges the gap between theoretical knowledge and practical implementation.  
