#!/usr/bin/python
# -*- coding: utf-8 -*-

import sys
import re

# import the Auth Helper class
import analytics_auth

from apiclient.errors import HttpError
from oauth2client.client import AccessTokenRefreshError

def main(argv):
  # Step 1. Get an analytics service object.
  service = analytics_auth.initialize_service()

  try:
    # Step 2. Get the user's first profile ID.
    profile_id = get_aitopics_profile_id(service)

    if profile_id:
      # Step 3. Query the Core Reporting API.
      start_date = argv[1]
      end_date = argv[2]
      page = argv[3]
      results = get_results(service, profile_id, start_date, end_date, page)

      # Step 4. Output the results.
      print_results(results)

  except TypeError, error:
    # Handle errors in constructing a query.
    print ('There was an error in constructing your query : %s' % error)

  except HttpError, error:
    # Handle API errors.
    print ('Arg, there was an API error : %s : %s' %
           (error.resp.status, error._get_reason()))

  except AccessTokenRefreshError:
    # Handle Auth errors.
    print ('The credentials have been revoked or expired, please re-run '
           'the application to re-authorize')

def get_aitopics_profile_id(service):
  # Get a list of all Google Analytics accounts for this user
  accounts = service.management().accounts().list().execute()

  if accounts.get('items'):
    # Get the first Google Analytics account
    firstAccountId = accounts.get('items')[2].get('id')

    # Get a list of all the Web Properties for the first account
    webproperties = service.management().webproperties().list(accountId=firstAccountId).execute()

    if webproperties.get('items'):
      # Get the first Web Property ID
      firstWebpropertyId = webproperties.get('items')[0].get('id')

      # Get a list of all Profiles for the first Web Property of the first Account
      profiles = service.management().profiles().list(
          accountId=firstAccountId,
          webPropertyId=firstWebpropertyId).execute()

      if profiles.get('items'):
        # return the first Profile ID
        return profiles.get('items')[0].get('id')

  return None

def get_results(service, profile_id, start_date, end_date, page):
  # Use the Analytics Service Object to query the Core Reporting API
  return service.data().ga().get(
      ids='ga:' + profile_id,
      filters=('ga:pagePath==%s' % page),
      start_date=start_date,
      end_date=end_date,
      dimensions='ga:previousPagePath',
      metrics='ga:pageViews').execute()

def print_results(results):
  # Print data nicely for the user.
  if results and results.get('rows'):
    pages = sorted(results.get('rows'), key=lambda row: int(row[1]), reverse=True)
    for page in pages[1:]:
      print '%s %d' % (page[0], int(page[1]))
  else:
    print 'No results found'

main(sys.argv)
