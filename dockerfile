FROM python:3.9-slim
WORKDIR /app
COPY gopale_app.py .
RUN pip install flask
EXPOSE 5000
CMD ["python", "gopale_app.py"]