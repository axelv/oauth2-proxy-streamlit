python streamlit app.py &

while [[ '$(curl -s -o /dev/null -w ''%{http_code}'' localhost:8501)' != '200' ]]; do sleep 1; done && 

/bin/oauth2-proxy --config=oauth2-proxy.cfg --cookie_secret=${python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'} &

# Wait for any process to exit
wait -n
  
# Exit with status of process that exited first
exit $?

