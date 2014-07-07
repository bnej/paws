paws
====

Pod Abstract Web Service - You know, for Pod.

What is PAWS?
-------------

PAWS is a web service/application based on the Pod::Abstract CPAN module which offers a search and browsing interface over Perl POD documentation.

It is designed to work as a universal Pod browser within a programming team, using open source tools and a straightforward architecture that lets you build it into any team's toolkit.

The search and indexing capabilities are built on Elasticsearch, so you can have a fast, accurate, full-text search of all of your CPAN modules and packaged source code.

Indexing can be done on the file system like traditional search tools, but can also be based on data fed from commits to your version control system so that you don't have to maintain a re-indexed tree of the code, and so that index response to commits can be as fast as possible.

Finally, PAWS includes markup, annotation and collaboration tools (still being developed) which integrate with the above.