
coverage:
	python3 -m coverage run test_msg2html.py
	python3 -m coverage html -d coverage_html

clean:
	rm -f TestAttachments/05/ef/at_0_1234_5678/HEART.jpeg
	rm -rf TestAttachments/bf
	rm -f test_*.html
	rm -rf test_links

distclean:
	rm -rf links
	rm -f ????.html ????_dbg.html
