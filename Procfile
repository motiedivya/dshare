web: python manage.py collectstatic --noinput && python manage.py migrate --noinput && gunicorn dshare.wsgi --log-file - --timeout 600 --workers 2 --threads 4
