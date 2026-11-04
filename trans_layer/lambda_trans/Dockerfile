FROM public.ecr.aws/lambda/python:3.12

# Install Python dependencies
COPY requirements.txt ${LAMBDA_TASK_ROOT}

RUN pip install \
    --no-cache-dir \
    -r requirements.txt

# Copy application code
COPY src/ ${LAMBDA_TASK_ROOT}/

# Lambda entry point
CMD ["handler.lambda_handler"]