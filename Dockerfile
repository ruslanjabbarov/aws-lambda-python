FROM public.ecr.aws/lambda/python:3.12
RUN dnf install openssl-devel expat-devel wget make automake gcc gcc-c++ kernel-devel swig tar gzip -y
COPY layer/requirements.txt ${LAMBDA_TASK_ROOT}
RUN wget https://nlnetlabs.nl/downloads/unbound/unbound-1.22.0.tar.gz
RUN tar -xzf unbound-1.22.0.tar.gz
RUN cd unbound-1.22.0 &&  ./configure --with-pyunbound --with-pythonmodule \
&& make && make install

RUN pip install -r requirements.txt
COPY src/aws_lambda_python ${LAMBDA_TASK_ROOT}/aws_lambda_python
RUN rm -rf unbound-1.22.0
CMD [ "aws_lambda_python/mpic_coordinator_lambda/mpic_coordinator_lambda_function.handler" ]
