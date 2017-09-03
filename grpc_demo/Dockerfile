FROM grpc/python:1.0-onbuild
ADD checker_client.py checker_server.py checker_pb2_grpc.py checker_pb2.py /
#RUN pip install -r requirements.txt
WORKDIR /
# For debugging.
#CMD ["sleep", "100000"]
CMD ["python", "checker_server.py"]
