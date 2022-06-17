FROM python:3.9.13-slim-bullseye
RUN mkdir /opt/flaskService
COPY flaskService.py /opt/flaskService/
COPY requirements.txt /opt/flaskService/
WORKDIR /opt/flaskService
RUN pip install -r requirements.txt
EXPOSE 5000
CMD [ "python", "flaskService.py" ]