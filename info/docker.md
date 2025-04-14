# Run app in Docker Container

## Create Docker Image

In `src` folder run script to create the appropriate Docker image.

```bash
docker build --progress=plain -t peregrina-app .
```

## Run Docker Container

To run Docker container use a command like this.

```bash
docker run --rm -p 38888:8888 -it peregrina-app
```

To set shared folders use volumes so your app can always pointing the appropriate paths.

```bash
docker run -v ${PWD}/settings.json:/app/settings.json `
            -v ${PWD}/books:/shared/books `
            -v ${PWD}/comics:/shared/comics `
            --rm -p 38888:8888 -it peregrina-app
```

## Using Docker Compose

A `docker-compose.yml` file is provided in the project root to simplify running the application.

To start the application using Docker Compose, navigate to the project root directory in your terminal and run:
```bash
bash docker-compose up -d
```
This command will start the container in the background.

To stop the application, use the following command from the same directory:


## Open app in Browser

http://localhost:38888/
