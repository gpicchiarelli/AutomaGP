;;;; semantic/catalog.lisp — the standards the platform is meant to implement
;;;;
;;;; What is registered here is what exists and where it is published, read
;;;; from the publishers' pages on 2026-10-03. None of it is implemented: no
;;;; standard has a construct catalog, a requirement, a test or evidence yet,
;;;; so none has a level of support. When one gets them, they are added to its
;;;; entry here, and the report changes by itself.
;;;;
;;;; A dependency is declared only where the specification's own list of
;;;; normative references says so. Where that list has not been read yet, the
;;;; entry says that in its note and declares none, instead of guessing.

(in-package #:automa-gp/semantic)

(defun %documents (&rest specs)
  "SPEC-DOCUMENTs from SPECS, each (ID TITLE URL [ROLE])."
  (mapcar (lambda (spec)
            (destructuring-bind (id title url &optional (role :normative)) spec
              (make-spec-document :id id :title title :url url :role role)))
          specs))

(defun %suites (&rest specs)
  "TEST-SUITEs from SPECS, each (ID NAME URL NOTE)."
  (mapcar (lambda (spec)
            (destructuring-bind (id name url &optional note) spec
              (make-test-suite :id id :name name :url url :note note)))
          specs))

(defparameter *w3c-tests-url* "https://w3c.github.io/rdf-tests/"
  "The W3C's index of its RDF and SPARQL tests and implementation reports.")

(defun %shipped-definitions ()
  "The STANDARD-DEFINITIONs the platform ships knowing about."
  (list
   (make-standard-definition
    :identifier :iri :name "Internationalized Resource Identifiers (IRIs)"
    :version "rfc3987" :release "RFC 3987, January 2005" :maturity :rfc
    :specification "https://www.rfc-editor.org/rfc/rfc3987"
    :documents (%documents '(:rfc3987 "RFC 3987: Internationalized Resource Identifiers (IRIs)"
                             "https://www.rfc-editor.org/rfc/rfc3987")))
   (make-standard-definition
    :identifier :bcp47 :name "Tags for Identifying Languages"
    :version "rfc5646" :release "RFC 5646, September 2009" :maturity :rfc
    :specification "https://www.rfc-editor.org/rfc/rfc5646"
    :documents (%documents '(:rfc5646 "RFC 5646: Tags for Identifying Languages"
                             "https://www.rfc-editor.org/rfc/rfc5646"))
    :note "BCP 47 is the series; RFC 5646 is the text of it that RDF 1.1 refers to.")
   (make-standard-definition
    :identifier :xsd-datatypes :name "W3C XML Schema Definition Language (XSD) 1.1 Part 2: Datatypes"
    :version "1.1" :release "W3C Recommendation 5 April 2012"
    :specification "https://www.w3.org/TR/xmlschema11-2/"
    :documents (%documents '(:xmlschema11-2 "W3C XML Schema Definition Language (XSD) 1.1 Part 2: Datatypes"
                             "https://www.w3.org/TR/xmlschema11-2/")))
   (make-standard-definition
    :identifier :rdf :name "RDF 1.1"
    :version "1.1" :release "W3C Recommendation 25 February 2014"
    :specification "https://www.w3.org/TR/rdf11-concepts/"
    :documents (%documents
                '(:concepts "RDF 1.1 Concepts and Abstract Syntax"
                  "https://www.w3.org/TR/rdf11-concepts/")
                '(:semantics "RDF 1.1 Semantics"
                  "https://www.w3.org/TR/rdf11-mt/"))
    :dependencies '("iri@rfc3987" "bcp47@rfc5646" "xsd-datatypes@1.1")
    :test-suites (%suites
                  (list :rdf-tests "W3C RDF and SPARQL tests" *w3c-tests-url*))
    :note "Dependencies are the normative references of RDF 1.1 Concepts, read on 2026-10-03.")
   (make-standard-definition
    :identifier :rdfs :name "RDF Schema 1.1"
    :version "1.1" :release "W3C Recommendation 25 February 2014"
    :specification "https://www.w3.org/TR/rdf-schema/"
    :documents (%documents
                '(:schema "RDF Schema 1.1" "https://www.w3.org/TR/rdf-schema/")
                '(:semantics "RDF 1.1 Semantics (RDFS entailment)"
                  "https://www.w3.org/TR/rdf11-mt/"))
    :dependencies '("rdf@1.1")
    :note "The vocabulary is RDF Schema 1.1; its entailment is defined in RDF 1.1 Semantics.")
   (make-standard-definition
    :identifier :ntriples :name "RDF 1.1 N-Triples"
    :version "1.1" :release "W3C Recommendation 25 February 2014"
    :specification "https://www.w3.org/TR/n-triples/"
    :documents (%documents '(:n-triples "RDF 1.1 N-Triples" "https://www.w3.org/TR/n-triples/"))
    :dependencies '("rdf@1.1")
    :test-suites (%suites
                  (list :n-triples-tests "W3C N-Triples tests"
                        "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-n-triples/")))
   (make-standard-definition
    :identifier :nquads :name "RDF 1.1 N-Quads"
    :version "1.1" :release "W3C Recommendation 25 February 2014"
    :specification "https://www.w3.org/TR/n-quads/"
    :documents (%documents '(:n-quads "RDF 1.1 N-Quads" "https://www.w3.org/TR/n-quads/"))
    :dependencies '("rdf@1.1")
    :test-suites (%suites
                  (list :n-quads-tests "W3C N-Quads tests"
                        "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-n-quads/")))
   (make-standard-definition
    :identifier :turtle :name "RDF 1.1 Turtle"
    :version "1.1" :release "W3C Recommendation 25 February 2014"
    :specification "https://www.w3.org/TR/turtle/"
    :documents (%documents '(:turtle "RDF 1.1 Turtle" "https://www.w3.org/TR/turtle/"))
    :dependencies '("rdf@1.1")
    :test-suites (%suites
                  (list :turtle-tests "W3C Turtle tests"
                        "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-turtle/")))
   (make-standard-definition
    :identifier :rdfxml :name "RDF 1.1 XML Syntax"
    :version "1.1" :release "W3C Recommendation 25 February 2014"
    :specification "https://www.w3.org/TR/rdf-syntax-grammar/"
    :documents (%documents '(:rdf-xml "RDF 1.1 XML Syntax" "https://www.w3.org/TR/rdf-syntax-grammar/"))
    :dependencies '("rdf@1.1")
    :test-suites (%suites
                  (list :rdf-xml-tests "W3C RDF/XML Syntax tests"
                        "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-xml/")))
   (make-standard-definition
    :identifier :jsonld :name "JSON-LD 1.1"
    :version "1.1" :release "W3C Recommendation 16 July 2020"
    :specification "https://www.w3.org/TR/json-ld11/"
    :documents (%documents
                '(:syntax "JSON-LD 1.1" "https://www.w3.org/TR/json-ld11/")
                '(:api "JSON-LD 1.1 Processing Algorithms and API"
                  "https://www.w3.org/TR/json-ld11-api/")
                '(:framing "JSON-LD 1.1 Framing" "https://www.w3.org/TR/json-ld11-framing/"))
    :dependencies '("rdf@1.1")
    :test-suites (%suites
                  (list :json-ld-tests "JSON-LD Test Suite"
                        "https://w3c.github.io/json-ld-api/tests/"))
    :note "That a JSON-LD processor depends on RDF 1.1 was not read from the references of its three documents yet.")
   (make-standard-definition
    :identifier :rdf12 :name "RDF 1.2"
    :version "1.2" :release "W3C Candidate Recommendation Snapshot 7 April 2026"
    :maturity :candidate-recommendation
    :specification "https://www.w3.org/TR/rdf12-concepts/"
    :documents (%documents '(:concepts "RDF 1.2 Concepts and Abstract Data Model"
                             "https://www.w3.org/TR/rdf12-concepts/"))
    :note "Not a Recommendation. docs/PROMPT-FASE-2.md cites it for quoted triples; it is not a target until it is one, or the owner decides otherwise.")
   (make-standard-definition
    :identifier :owl2 :name "OWL 2 Web Ontology Language"
    :version "2" :release "Second Edition, W3C Recommendation 11 December 2012"
    :specification "https://www.w3.org/TR/owl2-overview/"
    :documents (%documents
                '(:overview "OWL 2 Web Ontology Language Document Overview (Second Edition)"
                  "https://www.w3.org/TR/owl2-overview/" :informative)
                '(:syntax "OWL 2 Web Ontology Language Structural Specification and Functional-Style Syntax (Second Edition)"
                  "https://www.w3.org/TR/owl2-syntax/")
                '(:mapping "OWL 2 Web Ontology Language Mapping to RDF Graphs (Second Edition)"
                  "https://www.w3.org/TR/owl2-mapping-to-rdf/")
                '(:direct-semantics "OWL 2 Web Ontology Language Direct Semantics (Second Edition)"
                  "https://www.w3.org/TR/owl2-direct-semantics/")
                '(:rdf-based-semantics "OWL 2 Web Ontology Language RDF-Based Semantics (Second Edition)"
                  "https://www.w3.org/TR/owl2-rdf-based-semantics/")
                '(:profiles "OWL 2 Web Ontology Language Profiles (Second Edition)"
                  "https://www.w3.org/TR/owl2-profiles/")
                '(:conformance "OWL 2 Web Ontology Language Conformance (Second Edition)"
                  "https://www.w3.org/TR/owl2-conformance/")
                '(:xml-serialization "OWL 2 Web Ontology Language XML Serialization (Second Edition)"
                  "https://www.w3.org/TR/owl2-xml-serialization/")
                '(:primer "OWL 2 Web Ontology Language Primer (Second Edition)"
                  "https://www.w3.org/TR/owl2-primer/" :informative))
    :test-suites (%suites
                  (list :owl2-test-cases "OWL 2 test cases" nil
                        "Described by the Conformance document; to be located and pinned when the standard is acquired."))
    :note "The normative references of these documents have not been read yet, so no dependency is declared. OWL 2 (2012) predates RDF 1.1 (2014): which versions of RDF and XSD it names is for the acquisition step to extract, not to assume. Direct Semantics and RDF-Based Semantics are separate documents and are implemented separately.")
   (make-standard-definition
    :identifier :shacl :name "Shapes Constraint Language (SHACL)"
    :version "1.0" :release "W3C Recommendation 20 July 2017"
    :specification "https://www.w3.org/TR/shacl/"
    :documents (%documents
                '(:shacl "Shapes Constraint Language (SHACL)" "https://www.w3.org/TR/shacl/")
                '(:shacl-af "SHACL Advanced Features (Working Group Note)"
                  "https://www.w3.org/TR/shacl-af/" :informative))
    :dependencies '("rdf@1.1" "sparql@1.1" "turtle@1.1" "bcp47@rfc5646")
    :test-suites (%suites
                  (list :shacl-tests "SHACL Test Suite and Implementation Report"
                        "https://w3c.github.io/data-shapes/data-shapes-test-suite/"))
    :note "Dependencies are the normative references of the SHACL Recommendation, read on 2026-10-03.")
   (make-standard-definition
    :identifier :sparql :name "SPARQL 1.1"
    :version "1.1" :release "W3C Recommendation 21 March 2013"
    :specification "https://www.w3.org/TR/sparql11-overview/"
    :documents (%documents
                '(:overview "SPARQL 1.1 Overview"
                  "https://www.w3.org/TR/sparql11-overview/" :informative)
                '(:query "SPARQL 1.1 Query Language" "https://www.w3.org/TR/sparql11-query/")
                '(:update "SPARQL 1.1 Update" "https://www.w3.org/TR/sparql11-update/")
                '(:protocol "SPARQL 1.1 Protocol" "https://www.w3.org/TR/sparql11-protocol/")
                '(:results-json "SPARQL 1.1 Query Results JSON Format"
                  "https://www.w3.org/TR/sparql11-results-json/")
                '(:entailment "SPARQL 1.1 Entailment Regimes"
                  "https://www.w3.org/TR/sparql11-entailment/"))
    :test-suites (%suites
                  (list :sparql11-tests "SPARQL 1.1 test suite"
                        "https://www.w3.org/2009/sparql/docs/tests/"))
    :note "The other SPARQL 1.1 documents (XML and CSV/TSV results, Federated Query, Graph Store HTTP Protocol, Service Description) belong to the family and are not cataloged yet. No dependency is declared: the normative references have not been read yet.")
   (make-standard-definition
    :identifier :prov-o :name "PROV-O: The PROV Ontology"
    :version "2013" :release "W3C Recommendation 30 April 2013"
    :specification "https://www.w3.org/TR/prov-o/"
    :documents (%documents '(:prov-o "PROV-O: The PROV Ontology" "https://www.w3.org/TR/prov-o/"))
    :note "Cited by docs/PROMPT-FASE-2.md as the model of provenance.")
   (make-standard-definition
    :identifier :wikibase-data-model :name "Wikibase data model (Wikidata)"
    :version "unversioned" :maturity :living-document
    :release "Living wiki pages; the revision is pinned when the standard is acquired"
    :specification "https://www.mediawiki.org/wiki/Wikibase/DataModel"
    :documents (%documents
                '(:data-model "Wikibase/DataModel" "https://www.mediawiki.org/wiki/Wikibase/DataModel")
                '(:rdf-mapping "Wikibase/Indexing/RDF Dump Format"
                  "https://www.mediawiki.org/wiki/Wikibase/Indexing/RDF_Dump_Format")
                '(:statements "Help:Statements (Wikidata)"
                  "https://www.wikidata.org/wiki/Help:Statements" :informative)
                '(:wikidata-model "Wikidata:Data model"
                  "https://www.wikidata.org/wiki/Wikidata:Data_model" :informative))
    :note "Not a W3C standard and not versioned: its pages change. A statement carries qualifiers, references and a rank, and is not reduced to a triple.")))

(defun register-shipped-standards (&optional (registry *registry*))
  "Register in REGISTRY the standards this platform ships knowing about, and
return them. Registering again replaces them. None is implemented; see the
note at the top of this file."
  (with-registry (registry)
    (mapcar (lambda (definition)
              (register-standard definition :replace t))
            (%shipped-definitions))))

(register-shipped-standards)
