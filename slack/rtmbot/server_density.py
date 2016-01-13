import json
from datetime import datetime, timedelta
import pygal
import requests

from slacker import Slacker

API_KEY = "CHANGEME"
SLACK_API_KEY = "CHANGEME"

params = {
        'token':API_KEY
}

ACCOUNT_NAME = "CHANGEME" # first part of your url THISBIT.serverdensity.io
ACCOUNT_URL = "https://{0}.serverdensity.io".format(ACCOUNT_NAME)
API_BASE_URL = "https://api.serverdensity.io"
TOKEN_PARAM = "?token={0}".format(API_KEY)
ALERTS_TRIGGERED_URL = "{0}/alerts/triggered?token={1}&closed=false".format(API_BASE_URL, API_KEY)
ALERTS_CONFIGS_URL = "{0}/alerts/configs/".format(API_BASE_URL)
METRICS_GRAPHING_URL = API_BASE_URL + "/metrics/graphs/{0}" + TOKEN_PARAM
FETCH_FROM_INVENTORY_URL = "{0}/inventory/devices/".format(API_BASE_URL)

FETCH_FROM_INVENTORY_BY_NAME_URL = "{0}/inventory/devices/".format(API_BASE_URL)
MS_PER_MINUTE = 60000

DEBUG = True

slack = Slacker(SLACK_API_KEY)

def process_message(slack_data):

    if DEBUG:
        print "Data from Slack: {0}".format(slack_data['text'])

    message_data = slack_data['text'].split(' ')

    # remove the first [u'<@U042GJK0E>:', u'status', u'for', u'Jarvis']
    # when addressed via a room instead of directly
    if '@' in message_data[0]:
        del message_data[0]

    if "status" in message_data[0] and "for" in message_data[1]:
        item = fetch_from_inventory(message_data[-1])
        statuses = fetch_status(item)

        for status in statuses:
            outputs.append([
                slack_data['channel'],
                "{0} -> {1} -> {2}".format(status['fullName'], status['name'], status['value'])
            ])

    # graph memory for Jarvis
    if "graph" in message_data[0]:
        item = fetch_from_inventory(message_data[-1])
        fetch_graph(item, message_data[1])



def fetch_from_inventory(name):

    params['filter'] = json.dumps({
        'name': name
        }
    )
    if DEBUG:
        print "Fetching from inventory"

    r = requests.get(FETCH_FROM_INVENTORY_URL, params=params)
    if r.status_code != 200:
        print "Failed to fetch from inventory."
        return False

    if DEBUG:
        print "Fetched from inventory"
    return r.json()[0]

def fetch_status(item):

    params['filter'] = json.dumps({
            "loadAvrg":"all",
            "memory":{
                "memSwapUsed":"all",
                "memPhysUsed":"all"
            }
        }
    )

    now = datetime.now()
    then = now - timedelta(seconds=180)

    params['start'] = then.strftime('%Y-%m-%dT%H:%M:%S')
    params['end'] = now.strftime('%Y-%m-%dT%H:%M:%S')
    r = requests.get(METRICS_GRAPHING_URL.format(item.get('id')), params=params)

    data = []

    #msg.send measure.name + ' -> ' + measure.data[measure.data.length - 1].y
    for metric in r.json():
        if 'tree' in metric:
            for d in metric['tree']:
                data.append({
                    'fullName': metric.get('name'),
                    'name': d.get('name'),
                    'value': d.get('data')[-1].get('y')
            })
    return data

def fetch_graph(item, metric):
    params['filter'] = json.dumps({
            metric: "all"
        }
    )

    now = datetime.now()
    then = now - timedelta(seconds=1800)

    params['start'] = then.strftime('%Y-%m-%dT%H:%M:%S')
    params['end'] = now.strftime('%Y-%m-%dT%H:%M:%S')
    r = requests.get(METRICS_GRAPHING_URL.format(item.get('id')), params=params)

    metrics = r.json()

    metric_data = metrics[0]['tree'][0]

    dates = []
    values = []

    for i, data in enumerate(metric_data['data']):
        if not i % 10:
            dates.append(datetime.fromtimestamp(data['x']))
        values.append(data['y'])

    line_chart = pygal.Line(
        width=400,
        height=200,
        x_label_rotation=20,
        label_font_size=8)
    line_chart.title = metric
    line_chart.x_labels = map(str, dates)
    line_chart.add('', values)

    if DEBUG:
        print "Rending to file"

    line_chart.render_to_png('/tmp/bar_chart.png')
    line_chart.render_to_file('/tmp/bar_chart.svg')

    uploaded_file = slack.files.upload('/tmp/bar_chart.png')
    image_url = uploaded_file.body['file']['url']
    thumb_url = uploaded_file.body['file']['thumb_64']

    try:
        attachments = [
            {
                "author_name": "Yoshi",
                "author_link": "https://{0}.serverdensity.io".format(ACCOUNT_NAME),
                "author_icon": "https://www.serverdensity.com/assets/images/sd-logo.png",
                "fallback": "Requested Graph",
                "title": "Graph for {0}".format(metric),
                "title_link": image_url,
                "thumb_url": thumb_url,
                "color": "#7CD197",
                "text": "{0} -> {1}".format(params['start'], params['end']),
                "image_url": image_url,
            }
        ]
    except Exception as exception:
        print exception.message

    slack.chat.post_message(slack_data['channel'], '', attachments=attachments)

    if DEBUG:
        print "Graphing finished"
